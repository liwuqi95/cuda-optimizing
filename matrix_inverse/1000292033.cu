#include <sys/time.h>
#include <stdio.h>

// time stamp function in seconds
double getTimeStamp() {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (double) tv.tv_usec / 1000000 + tv.tv_sec;
}

// host side matrix addition
void h_inverse(float *A, float *B, int nx, int ny) {
    for (int i = 0; i < ny; i++)
        for (int j = 0; j < nx; j++)
            B[j * ny + i] = A[i * nx + j];
}

// device-side matrix addition
__global__ void f_inverse(float *A, float *B, int nx, int ny, int noElems) {
    __shared__ float sdata[32][33];


    int xBlock = blockIdx.x * blockDim.x;
    int yBlock = blockIdx.y * blockDim.y * 32;

    int xIndex = xBlock + threadIdx.x;
    int yIndex = yBlock + threadIdx.y * 32;

    if (xIndex < nx && yIndex < ny) {

        int index_in = yIndex * nx + xIndex;

        for (int i = 0; i < 32 && index_in < noElems; i++) {
            sdata[i][threadIdx.x] = A[index_in + nx * i];
        }

        __syncthreads();

        int index_out = (xBlock + threadIdx.y * 32) * ny + yBlock + threadIdx.x;

        for (int i = 0; i < 32 && index_out < noElems; i++) {
            B[index_out + i * ny] = sdata[threadIdx.x][i];
        }

    } else
        __syncthreads();
}

int main(int argc, char *argv[]) {
    // get program arguments
    if (argc != 3) {
        printf("Error: wrong number of args\n");
        exit(1);
    }


    int nx = atoi(argv[1]); // should check validity
    int ny = atoi(argv[2]); // should check validity

    int noElems = nx * ny;
    int bytes = noElems * sizeof(float);
    // but you may want to pad the matrices…

    // alloc memory host-side
    float *h_A = (float *) malloc(bytes);

    float *h_hR = (float *) malloc(bytes); // host result
    float *h_dR = (float *) malloc(bytes); // gpu result

    cudaHostRegister(h_A, bytes, 0);
    cudaHostRegister(h_dR, bytes, 0);

    // init matrices with random data

    int i, j;
    for (i = 0; i < ny; i++)
        for (j = 0; j < nx; j++)
            h_A[i * nx + j] = rand();



    // alloc memory dev-side
    float *d_A, *d_R;
    cudaMalloc((void **) &d_A, bytes);
    cudaMalloc((void **) &d_R, bytes);

    double timeStampA = getTimeStamp();
    //transfer data to dev
    cudaMemcpy(d_A, h_A, bytes, cudaMemcpyHostToDevice);


    // invoke Kernel
    dim3 block(32, 1);
    dim3 grid((nx + block.x - 1) / block.x, (ny + block.y * 32 - 1) / (block.y * 32));

    f_inverse << < grid, block >> > (d_A, d_R, nx, ny, noElems);
    cudaDeviceSynchronize();

    //copy data back
    cudaMemcpy(h_dR, d_R, bytes, cudaMemcpyDeviceToHost);

    double timeStampD = getTimeStamp();
    // free GPU resources
    cudaFree(d_A);
    cudaFree(d_R);
    cudaDeviceReset();

    // check result
    h_inverse(h_A, h_hR, nx, ny);

    bool correct = true;

    for (i = 0; i < nx * ny; i++)
        if (h_hR[i] != h_dR[i]) {
            correct = false;
            break;
        }

    if (!correct)
        printf("Error: Result Incorrect!\n");

    cudaHostUnregister(h_A);
    cudaHostUnregister(h_dR);


    // print out results
    printf("%.6f \n", timeStampD - timeStampA);
}
