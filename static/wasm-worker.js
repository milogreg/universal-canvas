let memory;

let exports;

let dataBitmap;

let pollingBitmap = false;

const env = {
    fillImageBitmap: (dataPtr, width, height) => {
        const data = new Uint8ClampedArray(
            new Uint8ClampedArray(memory.buffer, dataPtr, width * height * 4)
        );

        const imageData = new ImageData(data, width, height);

        pollingBitmap = true;
        setTimeout(async () => {
            const startTime = performance.now();

            // const options = {
            //     resizeWidth: 2048,
            //     resizeHeight: 2048,
            //     resizeQuality: "pixelated",
            // };

            const newDataBitmap = await createImageBitmap(imageData);

            if (dataBitmap) {
                dataBitmap.close();
            }

            dataBitmap = newDataBitmap;

            pollingBitmap = false;

            const endTime = performance.now();
            const executionTime = endTime - startTime;

            // console.log(`Execution time: ${executionTime} milliseconds`);
        }, 0);
    },

    imageBitmapFilled: () => {
        return !pollingBitmap;
    },

    renderImage: (
        offsetX,
        offsetY,
        zoom,

        clipX,
        clipY,

        clipWidth,
        clipHeight,

        updatedPixels,
        maxDetail,
        version
    ) => {
        if (!updatedPixels || !dataBitmap) {
            self.postMessage({
                type: "renderImage",

                data: null,
                offsetX,
                offsetY,
                zoom,

                clipX,
                clipY,

                clipWidth,
                clipHeight,

                maxDetail,
                version,
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

                clipX,
                clipY,

                clipWidth,
                clipHeight,

                maxDetail,
                version,
            },
            [dataBitmap]
        );

        dataBitmap = undefined;
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

self.onmessage = function (e) {
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

        zoom,
        viewportWidth,
        viewportHeight,

        version,

        imageSquareSize,

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

            exports.getOffsetFree();

            const fileUrl = URL.createObjectURL(fileData);
            self.postMessage({ type: "saveOffsetComplete", fileUrl: fileUrl });
            break;
        }

        case "updatePosition": {
            exports.updatePosition(
                offsetX,
                offsetY,
                zoom,
                viewportWidth,
                viewportHeight,
                version
            );

            self.postMessage({ type: "updatePositionComplete" });

            break;
        }

        case "resetPosition": {
            exports.resetPosition(viewportWidth, viewportHeight);

            self.postMessage({ type: "resetPositionComplete" });

            break;
        }

        case "renderImage": {
            exports.renderPixels();

            break;
        }

        case "makeImage": {
            const imageBytes = exports.makeImage(imageSquareSize);

            // Create a blob from the RGBA image data
            const size = imageSquareSize * imageSquareSize * 4;
            const imageArray = new Uint8ClampedArray(
                memory.buffer,
                imageBytes,
                size
            );
            const imageData = new ImageData(
                imageArray,
                imageSquareSize,
                imageSquareSize
            );
            const canvas = new OffscreenCanvas(
                imageSquareSize,
                imageSquareSize
            );
            const ctx = canvas.getContext("2d");
            ctx.putImageData(imageData, 0, 0);

            // Convert the canvas to a blob and create a download URL
            canvas.convertToBlob({ type: "image/png" }).then((blob) => {
                const imageUrl = URL.createObjectURL(blob);
                self.postMessage({ type: "makeImageComplete", imageUrl });
            });

            exports.freeImage(imageBytes, imageSquareSize);

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
        if (executionTime > 100) {
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

    // setTimeout(workCycleLoop, 100);
}
