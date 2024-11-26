let memory;

let exports;

let pixelData = new Uint8ClampedArray(0);

let oldPixelData = new Uint8ClampedArray(0);

const env = {
    renderImage: (
        dataPtr,
        width,
        height,
        offsetX,
        offsetY,
        zoom,

        oldDataPtr,
        oldWidth,
        oldHeight,
        oldOffsetX,
        oldOffsetY,
        oldZoom,

        updatedPixels,
        maxDetail
    ) => {
        if (width == 0) {
            throw new Error("Invalid width");
        }
        if (!updatedPixels) {
            self.postMessage({
                type: "renderImage",
                data: null,
                width,
                height,
                offsetX,
                offsetY,
                zoom,

                oldData: null,
                oldWidth,
                oldHeight,
                oldOffsetX,
                oldOffsetY,
                oldZoom,

                maxDetail,
            });

            return;
        }

        const startTime = performance.now();

        if (pixelData.byteLength < width * height * 4) {
            pixelData = new Uint8ClampedArray(
                new Uint8ClampedArray(
                    memory.buffer,
                    dataPtr,
                    width * height * 4
                )
            );
        } else {
            pixelData.set(
                new Uint8ClampedArray(
                    memory.buffer,
                    dataPtr,
                    width * height * 4
                )
            );
        }

        const data = new Uint8ClampedArray(
            pixelData.buffer,
            0,
            width * height * 4
        );

        if (oldPixelData.byteLength < oldWidth * oldHeight * 4) {
            oldPixelData = new Uint8ClampedArray(
                new Uint8ClampedArray(
                    memory.buffer,
                    oldDataPtr,
                    oldWidth * oldHeight * 4
                )
            );
        } else {
            oldPixelData.set(
                new Uint8ClampedArray(
                    memory.buffer,
                    oldDataPtr,
                    oldWidth * oldHeight * 4
                )
            );
        }

        const oldData = new Uint8ClampedArray(
            new Uint8ClampedArray(
                memory.buffer,
                oldDataPtr,
                oldWidth * oldHeight * 4
            )
        );

        const endTime = performance.now();
        const executionTime = endTime - startTime;

        console.log(`Execution time: ${executionTime} milliseconds`);

        self.postMessage({
            type: "renderImage",
            data,
            width,
            height,
            offsetX,
            offsetY,
            zoom,

            oldData,
            oldWidth,
            oldHeight,
            oldOffsetX,
            oldOffsetY,
            oldZoom,

            maxDetail,
        });
    },
    printString: (ptr, len) => {
        // Create a DataView or Uint8Array to access the memory buffer
        const bytes = new Uint8Array(memory.buffer, ptr, len);

        // Decode the UTF-8 string
        const string = new TextDecoder("utf-8").decode(bytes);

        // Print the string
        console.log(string);
    },

    getTime: () => {
        return performance.now();
    },
};

fetch("example.wasm", { headers: { "Content-Type": "application/wasm" } })
    .then((response) => {
        if (!response.ok) {
            throw new Error(`Failed to load WASM file: ${response.statusText}`);
        }
        return response.arrayBuffer();
    })
    .then((bytes) => WebAssembly.instantiate(bytes, { env }))
    .then((results) => {
        exports = results.instance.exports;
        memory = exports.memory;

        exports.init();

        self.postMessage({ type: "initComplete" });
    })
    .catch((error) => {
        console.error("Error loading or instantiating WASM:", error);
    });

self.onmessage = async function (e) {
    const {
        type,
        canvasWidth,
        canvasHeight,
        offsetArray,
        offsetX,
        offsetY,
        mouseX,
        mouseY,
        zoomDelta,

        findImageData,
    } = e.data;
    switch (type) {
        case "setOffset": {
            const size = offsetArray.length;
            const offsetPtr = exports.setOffsetAlloc(size);

            const offsetMemory = new Uint8Array(memory.buffer, offsetPtr, size);

            offsetMemory.set(offsetArray);

            exports.setOffset();

            self.postMessage({ type: "setOffsetComplete" });
            break;
        }

        case "findImage": {
            const size = findImageData.data.length;

            const offsetPtr = exports.findImageAlloc(size);

            const offsetMemory = new Uint8ClampedArray(
                memory.buffer,
                offsetPtr,
                size
            );

            offsetMemory.set(findImageData.data);

            exports.findImage();

            self.postMessage({ type: "findImageComplete" });
            break;
        }

        case "saveOffset": {
            const offsetPtr = exports.getOffsetAlloc();
            const offsetLen = exports.getOffsetLen();

            const offsetArray = new Uint8Array(
                memory.buffer,
                offsetPtr,
                offsetLen
            );

            const fileData = new Blob([offsetArray]);
            const fileUrl = URL.createObjectURL(fileData);
            self.postMessage({ type: "saveOffsetComplete", fileUrl: fileUrl });
            break;
        }

        case "zoomViewport": {
            exports.zoomViewport(
                canvasWidth,
                canvasHeight,
                mouseX,
                mouseY,
                zoomDelta
            );

            self.postMessage({ type: "zoomViewportComplete" });

            break;
        }

        case "moveViewport": {
            exports.moveViewport(canvasWidth, canvasHeight, offsetX, offsetY);

            self.postMessage({ type: "moveViewportComplete" });

            break;
        }

        case "renderImage": {
            exports.renderPixels();

            break;
        }

        case "workCycle": {
            workCycleLoop();

            break;
        }

        default:
            console.error("Unknown message type from main thread:", type);
    }
};

const channel = new MessageChannel();
channel.port1.onmessage = workCycleLoop;

function workCycleLoop() {
    if (exports) {
        const startTime = performance.now();
        const res = exports.workCycle();
        const endTime = performance.now();
        const executionTime = endTime - startTime;
        if (res && executionTime > 3) {
            console.log(
                `workCycle execution time: ${executionTime} milliseconds`
            );
        }
    }

    channel.port2.postMessage("");
}
