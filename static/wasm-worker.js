let memory;

let exports;

let dataBitmap;
let oldDataBitmap;

let pollingBitmap = false;

const env = {
    fillImageBitmap: (
        dataPtr,
        width,
        height,
        oldDataPtr,
        oldWidth,
        oldHeight
    ) => {
        dataBitmap = undefined;
        oldDataBitmap = undefined;

        const data = new Uint8ClampedArray(
            memory.buffer,
            dataPtr,
            width * height * 4
        );

        const oldData = new Uint8ClampedArray(
            memory.buffer,
            oldDataPtr,
            oldWidth * oldHeight * 4
        );

        const imageData = new ImageData(data, width, height);

        const oldImageData = new ImageData(oldData, oldWidth, oldHeight);

        pollingBitmap = true;
        setTimeout(async () => {
            const startTime = performance.now();

            [dataBitmap, oldDataBitmap] = await Promise.all([
                createImageBitmap(imageData),
                createImageBitmap(oldImageData),
            ]);

            pollingBitmap = false;

            const endTime = performance.now();
            const executionTime = endTime - startTime;

            // console.log(`Execution time: ${executionTime} milliseconds`);
        }, 0);
    },

    imageBitmapFilled: () => {
        return !!dataBitmap && !!oldDataBitmap;
    },

    renderImage: (
        offsetX,
        offsetY,
        zoom,

        oldOffsetX,
        oldOffsetY,
        oldZoom,

        updatedPixels,
        maxDetail
    ) => {
        if (!updatedPixels) {
            self.postMessage({
                type: "renderImage",

                data: null,
                offsetX,
                offsetY,
                zoom,

                oldData: null,
                oldOffsetX,
                oldOffsetY,
                oldZoom,

                maxDetail,
            });

            return;
        }

        self.postMessage(
            {
                type: "renderImage",

                data: dataBitmap,
                offsetX,
                offsetY,
                zoom,

                oldData: oldDataBitmap,
                oldOffsetX,
                oldOffsetY,
                oldZoom,

                maxDetail,
            },
            [dataBitmap, oldDataBitmap]
        );
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
            exports.zoomViewport(mouseX, mouseY, zoomDelta);

            self.postMessage({ type: "zoomViewportComplete" });

            break;
        }

        case "moveViewport": {
            exports.moveViewport(offsetX, offsetY);

            self.postMessage({ type: "moveViewportComplete" });

            break;
        }

        case "resizeViewport": {
            exports.resizeViewport(canvasWidth, canvasHeight);

            self.postMessage({ type: "resizeViewportComplete" });

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

let workCycleSleepTime = 1;
async function workCycleLoop() {
    let backoff = true;
    if (exports) {
        const startTime = performance.now();
        backoff = !exports.workCycle() || pollingBitmap;
        const endTime = performance.now();
        const executionTime = endTime - startTime;
        if (executionTime > 3) {
            console.log(
                `workCycle execution time: ${executionTime} milliseconds`
            );
        }
    }

    if (backoff) {
        // console.log(`sleeping ${workCycleSleepTime} ms...`);

        const prevWorkCycleSleepTime = workCycleSleepTime;
        workCycleSleepTime = Math.min(workCycleSleepTime * 2, 100);
        setTimeout(workCycleLoop, prevWorkCycleSleepTime);
    } else {
        workCycleSleepTime = 1;
        channel.port2.postMessage("");
    }
}
