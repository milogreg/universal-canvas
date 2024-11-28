"use strict";

// Set up the canvas
const canvas = document.getElementById("main-canvas");

const ctx = canvas.getContext("2d", {
    alpha: false,
});

canvas.width = 1024;
canvas.height = canvas.width;

canvas.style.opacity = "0";

// Create an observer to track changes in the canvas's client width and height
const observer = new ResizeObserver((entries) => {
    for (const entry of entries) {
        const { clientWidth, clientHeight } = entry.target;

        canvas.width = clientWidth;
        canvas.height = clientHeight;

        renderImageFromCache();

        upscaleDataBitmap();
        imageDirty = true;

        if (workerInitialized) {
            worker.postMessage({
                type: "resizeViewport",
                canvasWidth: canvas.width,
                canvasHeight: canvas.height,
            });
        }
    }
});

// Observe the canvas element
observer.observe(canvas);

const setPositionButton = document.getElementById("set-position");
const saveOffsetButton = document.getElementById("save-offset");
const clickZoomToggle = document.getElementById("click-zoom-toggle");

// Set up the worker
const worker = new Worker("wasm-worker.js");

let workerInitialized = false;

let loading = false;

let dataBitmap;
let oldDataBitmap;

let imageDirty = true;

let renderCache;

function renderImageFromCache() {
    if (renderCache) {
        const { offsetX, offsetY, zoom, oldOffsetX, oldOffsetY, oldZoom } =
            renderCache;
        renderImage(
            null,
            offsetX,
            offsetY,
            zoom,
            null,
            oldOffsetX,
            oldOffsetY,
            oldZoom,
            false
        );
    }
}

async function renderImage(
    data,
    offsetX,
    offsetY,
    zoom,

    oldData,
    oldOffsetX,
    oldOffsetY,
    oldZoom,

    maxDetail
) {
    if ((!data && !renderCache) || (data && data.width === 0)) {
        return;
    }

    if (!renderCache) {
        loading = false;
        canvasFadeIn();
    }

    imageDirty = !maxDetail;

    if (data) {
        if (dataBitmap) {
            dataBitmap.close();
        }

        if (oldDataBitmap) {
            oldDataBitmap.close();
        }

        dataBitmap = data;
        oldDataBitmap = oldData;

        upscaleDataBitmap();
    }

    const imageChanged =
        data ||
        offsetX !== renderCache.offsetX ||
        offsetY !== renderCache.offsetY ||
        zoom !== renderCache.zoom ||
        oldOffsetX !== renderCache.oldOffsetX ||
        oldOffsetY !== renderCache.oldOffsetY ||
        oldZoom !== renderCache.oldZoom;

    renderCache = {
        offsetX,
        offsetY,
        zoom,

        oldOffsetX,
        oldOffsetY,
        oldZoom,
    };

    const startTime = performance.now();

    ctx.imageSmoothingEnabled = imageChanged;

    ctx.clearRect(0, 0, canvas.width, canvas.height);

    ctx.drawImage(
        dataBitmap,
        0,
        0,
        dataBitmap.width,
        dataBitmap.height,
        offsetX,
        offsetY,
        canvas.width * zoom,
        canvas.height * zoom
    );

    ctx.drawImage(
        oldDataBitmap,
        0,
        0,
        oldDataBitmap.width,
        oldDataBitmap.height,
        oldOffsetX,
        oldOffsetY,
        canvas.width * oldZoom,
        canvas.height * oldZoom
    );

    const endTime = performance.now();
    const executionTime = endTime - startTime;

    if (executionTime > 3) {
        console.log(`drawImage execution time: ${executionTime} milliseconds`);
    }
}

async function upscaleDataBitmap() {
    if (!dataBitmap || !oldDataBitmap) {
        return;
    }

    const nextPowerOfTwoSquareSize = Math.pow(
        2,
        Math.ceil(Math.log2(canvas.width))
    );

    if (
        nextPowerOfTwoSquareSize <= dataBitmap.width ||
        nextPowerOfTwoSquareSize <= oldDataBitmap.width
    ) {
        return;
    }

    const options = {
        resizeWidth: nextPowerOfTwoSquareSize,
        resizeHeight: nextPowerOfTwoSquareSize,
        resizeQuality: "pixelated",
    };

    const prevDataBitmap = dataBitmap;
    const prevOldDataBitmap = oldDataBitmap;

    const [newDataBitmap, newOldDataBitmap] = await Promise.all([
        createImageBitmap(dataBitmap, options),
        createImageBitmap(oldDataBitmap, options),
    ]);

    if (dataBitmap === prevDataBitmap && oldDataBitmap === prevOldDataBitmap) {
        dataBitmap = newDataBitmap;
        oldDataBitmap = newOldDataBitmap;
        prevDataBitmap.close();
        prevOldDataBitmap.close();
    } else {
        newDataBitmap.close();
        newOldDataBitmap.close();
    }
}

let canvasFadingIn = false;
let canvasFadingOut = false;

async function canvasFadeIn() {
    const animationDuration = 1000; // 1 second
    const animationStartTime = performance.now();

    if (canvasFadingIn) {
        return;
    }

    canvasFadingOut = false;
    canvasFadingIn = true;

    const startingOpacity = Number(canvas.style.opacity);

    function animateOpacity() {
        const currentTime = performance.now();
        const elapsed = currentTime - animationStartTime;

        const opacity = Math.min(
            1,
            startingOpacity + elapsed / animationDuration
        );

        canvas.style.opacity = opacity;

        if (opacity < 1 && canvasFadingIn) {
            requestAnimationFrame(animateOpacity);
        } else {
            canvasFadingIn = false;
        }
    }

    animateOpacity();
}

async function canvasFadeOut() {
    const animationDuration = 1000; // 1 second
    const animationStartTime = performance.now();

    if (canvasFadingOut) {
        return;
    }

    canvasFadingOut = true;
    canvasFadingIn = false;

    const startingOpacity = Number(canvas.style.opacity);

    function animateOpacity() {
        const currentTime = performance.now();
        const elapsed = currentTime - animationStartTime;
        const opacity = Math.max(
            0,
            startingOpacity - elapsed / animationDuration
        );

        canvas.style.opacity = opacity;

        if (opacity > 0 && canvasFadingOut) {
            requestAnimationFrame(animateOpacity);
        } else {
            canvasFadingOut = false;
        }
    }

    animateOpacity();
}

worker.postMessage({ type: "workCycle" });

worker.onmessage = async function (e) {
    const {
        type,
        fileUrl,

        data,
        offsetX,
        offsetY,
        zoom,

        oldData,
        oldOffsetX,
        oldOffsetY,
        oldZoom,

        maxDetail,
    } = e.data;
    switch (type) {
        case "initComplete": {
            await new Promise((resolve) => {
                const handleWorkerMessage = (e) => {
                    if (e.data.type === "resizeViewportComplete") {
                        worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        resolve();
                    }
                };
                worker.addEventListener("message", handleWorkerMessage);
                worker.postMessage({
                    type: "resizeViewport",
                    canvasWidth: canvas.width,
                    canvasHeight: canvas.height,
                });
            });

            workerInitialized = true;

            break;
        }

        case "setOffsetComplete":
            break;
        case "saveOffsetComplete":
            const downloadLink = document.createElement("a");
            downloadLink.href = fileUrl;
            downloadLink.download = "position.bin";
            downloadLink.click();
            // document.body.removeChild(downloadLink);

            break;

        case "renderImage": {
            {
                renderImage(
                    data,
                    offsetX,
                    offsetY,
                    zoom,

                    oldData,
                    oldOffsetX,
                    oldOffsetY,
                    oldZoom,

                    maxDetail
                );

                break;
            }
        }

        case "zoomViewportComplete": {
            break;
        }

        case "moveViewportComplete": {
            break;
        }

        case "resizeViewportComplete": {
            break;
        }

        case "findImageComplete": {
            break;
        }

        default:
            console.error("Unknown message type from worker:", type);
    }
};

let clickZoomEnabled = clickZoomToggle.checked;

clickZoomToggle.addEventListener("change", () => {
    clickZoomEnabled = clickZoomToggle.checked;
});

async function zoomOnMouseHold() {
    let lastFrameTime = performance.now();
    let isMouseDown = false;
    let mouseX = 0;
    let mouseY = 0;

    const setMousePosition = (event) => {
        mouseX = event.offsetX;
        mouseY = event.offsetY;
    };

    const setTouchPosition = (event) => {
        mouseX = event.touches[0].clientX;
        mouseY = event.touches[0].clientY;
    };

    const startZoom = () => {
        isMouseDown = true;
    };

    const stopZoom = () => {
        isMouseDown = false;
    };

    const drags = [];

    async function handleMouseMoveDragging(event) {
        if ((event.buttons & 1) == 1 && !clickZoomEnabled) {
            drags.push({
                offsetX: event.movementX,
                offsetY: event.movementY,
            });
        }
    }

    const pressedKeys = {};

    document.addEventListener("keydown", (event) => {
        const arrowKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
        if (arrowKeys.includes(event.key)) {
            event.preventDefault();
            pressedKeys[event.key] = true;
        }
    });

    document.addEventListener("keyup", (event) => {
        const arrowKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
        if (arrowKeys.includes(event.key)) {
            event.preventDefault();
            pressedKeys[event.key] = false;
        }
    });

    // canvas.addEventListener("mousemove", handleMouseMoveDragging);

    canvas.addEventListener("mousedown", startZoom);
    canvas.addEventListener("mouseup", stopZoom);
    canvas.addEventListener("mousemove", setMousePosition);
    canvas.addEventListener("mousemove", handleMouseMoveDragging);

    canvas.addEventListener("touchstart", (event) => {
        event.preventDefault();
        startZoom();
        setTouchPosition(event);
    });

    canvas.addEventListener("touchend", (event) => {
        event.preventDefault();
        stopZoom();
    });

    canvas.addEventListener("touchmove", (event) => {
        event.preventDefault();
        setTouchPosition(event);
    });

    let zoomRate =
        parseFloat(document.getElementById("zoom-rate-input").value) || 4;

    const zoomRateInput = document.getElementById("zoom-rate-input");

    zoomRateInput.addEventListener("input", () => {
        const newZoomRate = parseFloat(zoomRateInput.value);
        if (!isNaN(newZoomRate)) {
            zoomRate = newZoomRate;
        }
    });

    let scrollZoomRate =
        parseFloat(document.getElementById("scroll-zoom-rate-input").value) ||
        0;

    const scrollZoomRateInput = document.getElementById(
        "scroll-zoom-rate-input"
    );

    scrollZoomRateInput.addEventListener("input", () => {
        const newScrollZoomRate = parseFloat(scrollZoomRateInput.value);
        if (!isNaN(newScrollZoomRate)) {
            scrollZoomRate = newScrollZoomRate;
        }
    });

    const scrolls = [];

    canvas.addEventListener("wheel", async (event) => {
        event.preventDefault();

        scrolls.push({
            mouseX: event.offsetX,
            mouseY: event.offsetY,
            deltaY: event.deltaY,
        });
    });

    const loop = async () => {
        const currentFrameTime = performance.now();
        const deltaTime = (currentFrameTime - lastFrameTime) / 1000; // Convert to seconds
        lastFrameTime = currentFrameTime;

        const zoomFactor = Math.pow(
            Math.pow(2, Math.pow(2, zoomRate)),
            deltaTime
        );

        const scrollZoomFactor = Math.pow(
            Math.pow(2, Math.pow(2, scrollZoomRate)),
            0.1
        );

        if (workerInitialized) {
            if (loading) {
                scrolls.length = 0;
                drags.length = 0;
            } else {
                imageDirty =
                    imageDirty ||
                    (isMouseDown && clickZoomEnabled) ||
                    scrolls.length > 0 ||
                    drags.length > 0 ||
                    pressedKeys["ArrowUp"] ||
                    pressedKeys["ArrowDown"] ||
                    pressedKeys["ArrowLeft"] ||
                    pressedKeys["ArrowRight"];

                scrolls.forEach(async (scroll) => {
                    worker.postMessage({
                        type: "zoomViewport",
                        mouseX: scroll.mouseX,
                        mouseY: scroll.mouseY,
                        zoomDelta:
                            scroll.deltaY > 0
                                ? 1 / scrollZoomFactor
                                : scrollZoomFactor,
                    });
                });

                scrolls.length = 0;

                drags.forEach(async (drag) => {
                    worker.postMessage({
                        type: "moveViewport",
                        offsetX: drag.offsetX,
                        offsetY: drag.offsetY,
                    });
                });

                drags.length = 0;

                if (isMouseDown && clickZoomEnabled) {
                    worker.postMessage({
                        type: "zoomViewport",
                        mouseX: mouseX,
                        mouseY: mouseY,
                        zoomDelta: zoomFactor,
                    });
                }

                if (
                    pressedKeys["ArrowUp"] ||
                    pressedKeys["ArrowDown"] ||
                    pressedKeys["ArrowLeft"] ||
                    pressedKeys["ArrowRight"]
                ) {
                    let offsetX = 0;
                    let offsetY = 0;

                    if (pressedKeys["ArrowUp"]) {
                        offsetY -= canvas.width * deltaTime;
                    }
                    if (pressedKeys["ArrowDown"]) {
                        offsetY += canvas.width * deltaTime;
                    }
                    if (pressedKeys["ArrowLeft"]) {
                        offsetX -= canvas.width * deltaTime;
                    }
                    if (pressedKeys["ArrowRight"]) {
                        offsetX += canvas.width * deltaTime;
                    }

                    worker.postMessage({
                        type: "moveViewport",
                        offsetX,
                        offsetY,
                    });
                }
            }

            // TODO calculate imageDirty properly so it doesn't need to be forced to true
            imageDirty = true;

            if (imageDirty || loading) {
                worker.postMessage({
                    type: "renderImage",
                });
            }
        }

        requestAnimationFrame(loop);
    };

    requestAnimationFrame(loop);
}

zoomOnMouseHold();

saveOffsetButton.onclick = async () => {
    const myPromise = new Promise((resolve) => {
        const handleWorkerMessage = (e) => {
            if (e.data.type === "saveOffsetComplete") {
                worker.removeEventListener("message", handleWorkerMessage);
                resolve();
            }
        };
        worker.addEventListener("message", handleWorkerMessage);
        worker.postMessage({
            type: "saveOffset",
        });
    });

    await myPromise;
};

function readFileIntoArray(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const arrayBuffer = reader.result;
            const uint8Array = new Uint8Array(arrayBuffer);
            resolve(uint8Array);
        };
        reader.onerror = reject;
        reader.readAsArrayBuffer(file);
    });
}

let fileInputContents;

const fileInput = document.getElementById("file-input");
fileInput.addEventListener("change", async (event) => {
    const file = event.target.files[0];
    fileInputContents = await readFileIntoArray(file);
});

setPositionButton.onclick = async () => {
    if (fileInputContents && fileInputContents.length >= 1) {
        canvasFadeOut();

        renderCache = undefined;
        imageDirty = true;
        loading = true;

        await new Promise((resolve) => {
            const handleWorkerMessage = (e) => {
                if (e.data.type === "setOffsetComplete") {
                    worker.removeEventListener("message", handleWorkerMessage);
                    resolve();
                }
            };
            worker.addEventListener("message", handleWorkerMessage);
            worker.postMessage({
                type: "setOffset",
                // offsetArray: Array.from({ length: 1000 }, () =>
                //     Math.floor(Math.random() * 3)
                // ),
                offsetArray: fileInputContents,
            });
        });
    }
};

const findImageInput = document.getElementById("find-image-input");
const findImageDropZone = document.getElementById("find-image-drop-zone");

async function handleFile(file) {
    try {
        const image = await loadImage(file);
        const resizedImage = resizeImage(image, 1024, 1024);
        const imageData = getImageData(resizedImage);

        // Use the imageData as needed
        canvasFadeOut();

        renderCache = undefined;
        imageDirty = true;
        loading = true;

        await new Promise((resolve) => {
            const handleWorkerMessage = (e) => {
                if (e.data.type === "findImageComplete") {
                    worker.removeEventListener("message", handleWorkerMessage);
                    resolve();
                }
            };
            worker.addEventListener("message", handleWorkerMessage);
            worker.postMessage({
                type: "findImage",
                findImageData: imageData,
            });
        });
    } catch (error) {
        console.error("Error processing file:", error);
    }
}

// Event listener for file input
findImageInput.addEventListener("change", (event) => {
    const file = event.target.files[0];
    if (file) {
        handleFile(file);
    }
});

// Drag-and-drop events
findImageDropZone.addEventListener("dragover", (event) => {
    event.preventDefault();
    findImageDropZone.style.backgroundColor = "#f0f0f0"; // Highlight the drop zone
});

findImageDropZone.addEventListener("dragleave", (event) => {
    event.preventDefault();
    findImageDropZone.style.backgroundColor = ""; // Reset the background
});

findImageDropZone.addEventListener("drop", (event) => {
    event.preventDefault();
    findImageDropZone.style.backgroundColor = ""; // Reset the background
    const file = event.dataTransfer.files[0];
    if (file) {
        handleFile(file);
    }
});

function loadImage(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => {
            const image = new Image();
            image.onload = () => resolve(image);
            image.onerror = reject;
            image.src = reader.result;
        };
        reader.onerror = reject;
        reader.readAsDataURL(file);
    });
}

function resizeImage(image, maxWidth, maxHeight) {
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");

    // Calculate the new dimensions while maintaining aspect ratio
    const aspectRatio = image.width / image.height;

    let newWidth = maxWidth;
    let newHeight = maxHeight;

    if (aspectRatio > 1) {
        // Landscape image (width is greater than height)
        newHeight = maxWidth / aspectRatio;
    } else {
        // Portrait image or square (height is greater or equal to width)
        newWidth = maxHeight * aspectRatio;
    }

    // Set the canvas dimensions to the new size
    canvas.width = maxWidth;
    canvas.height = maxHeight;

    // Draw the resized image
    ctx.drawImage(image, 0, 0, newWidth, newHeight);

    return canvas;
}

function getImageData(canvas) {
    const ctx = canvas.getContext("2d");
    return ctx.getImageData(0, 0, canvas.width, canvas.height);
}
