"use strict";

class ClientPosition {
    constructor(zoom, offsetX, offsetY, canvasWidth, canvasHeight) {
        this.zoom = zoom;
        this.offsetX = offsetX;
        this.offsetY = offsetY;
        this.canvasWidth = canvasWidth;
        this.canvasHeight = canvasHeight;
    }

    updatePosition(mouseX, mouseY, zoomDelta) {
        this.zoom *= zoomDelta;
        this.offsetX = mouseX - (mouseX - this.offsetX) * zoomDelta;
        this.offsetY = mouseY - (mouseY - this.offsetY) * zoomDelta;
    }

    move(offsetX, offsetY) {
        this.offsetX += offsetX;
        this.offsetY += offsetY;
    }

    updateDimensions(canvasWidth, canvasHeight) {
        if (
            this.canvasWidth === canvasWidth &&
            this.canvasHeight === canvasHeight
        ) {
            return;
        }

        this.offsetX /= this.canvasWidth;
        this.offsetY /= this.canvasHeight;

        this.canvasWidth = canvasWidth;
        this.canvasHeight = canvasHeight;

        this.offsetX *= this.canvasWidth;
        this.offsetY *= this.canvasHeight;
    }
}

const canvasContainer = document.getElementById("canvas-container");

const displayCanvas = document.getElementById("display-canvas");
displayCanvas.width = 2048;
displayCanvas.height = 2048;

const displayCtx = displayCanvas.getContext("bitmaprenderer");

const oldDisplayCanvas = document.getElementById("old-display-canvas");
oldDisplayCanvas.width = 2048;
oldDisplayCanvas.height = 2048;

const oldDisplayCtx = oldDisplayCanvas.getContext("bitmaprenderer");

const canvasLoadingAnimation = document.getElementById("canvas-loading");
canvasLoadingAnimation.style.opacity = 1;

const setPositionButton = document.getElementById("set-position");
const saveOffsetButton = document.getElementById("save-offset");
const clickZoomToggle = document.getElementById("click-zoom-toggle");

// Set up the worker
const worker = new Worker("wasm-worker.js");

let workerInitialized = false;

let loading = true;

let imageDirty = true;

let cachedPosition = new ClientPosition(1, 0, 0, 1, 1);
let oldCachedPosition = new ClientPosition(1, 0, 0, 1, 1);

// Create an observer to track changes in the canvas's client width and height
const observer = new ResizeObserver((entries) => {
    for (const entry of entries) {
        const { clientWidth, clientHeight } = entry.target;

        canvasContainer.width = clientWidth;
        canvasContainer.height = clientHeight;

        // renderImageFromCache();

        cachedPosition.updateDimensions(clientWidth, clientHeight);
        oldCachedPosition.updateDimensions(clientWidth, clientHeight);

        renderWake();

        if (workerInitialized) {
            worker.postMessage({
                type: "resizeViewport",
                canvasWidth: canvasContainer.width,
                canvasHeight: canvasContainer.height,
            });
        }
    }
});

// Observe the canvas element
observer.observe(canvasContainer);

let pushCache;

function renderImage(
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
    if (!pushCache) {
        pushCache = {};
    }

    if (data) {
        if (pushCache.data) {
            pushCache.data.close();
        }
        pushCache.data = data;

        cachedPosition = new ClientPosition(
            zoom,
            offsetX,
            offsetY,
            canvasContainer.width,
            canvasContainer.height
        );
    }

    if (oldData) {
        if (pushCache.oldData) {
            pushCache.oldData.close();
        }
        pushCache.oldData = oldData;

        oldCachedPosition = new ClientPosition(
            oldZoom,
            oldOffsetX,
            oldOffsetY,
            canvasContainer.width,
            canvasContainer.height
        );
    }

    renderWake();
}

const observe1 = new PerformanceObserver((list) => {
    console.log(list.getEntries());
});

observe1.observe({ type: "long-animation-frame", buffered: true });

function pushImage() {
    let data, offsetX, offsetY, zoom, oldData, oldOffsetX, oldOffsetY, oldZoom;
    if (pushCache) {
        data = pushCache.data;
        oldData = pushCache.oldData;
        pushCache = undefined;
    }

    offsetX = cachedPosition.offsetX;
    offsetY = cachedPosition.offsetY;
    zoom = cachedPosition.zoom;

    oldOffsetX = oldCachedPosition.offsetX;
    oldOffsetY = oldCachedPosition.offsetY;
    oldZoom = oldCachedPosition.zoom;

    if (loading) {
        if (!data) {
            return;
        }

        loading = false;
        canvasFadeIn();
    }
    const startTime = performance.now();

    if (data) {
        displayCtx.transferFromImageBitmap(data);
        oldDisplayCtx.transferFromImageBitmap(oldData);
    }

    transformCanvas(displayCanvas, offsetX, offsetY, zoom);
    transformCanvas(oldDisplayCanvas, oldOffsetX, oldOffsetY, oldZoom);

    const endTime = performance.now();
    const totalTime = endTime - startTime;
    if (totalTime > 3) {
        console.log("render time:", totalTime);
    }
}

function transformCanvas(toTransform, offsetX, offsetY, zoom) {
    const squareRatio = canvasContainer.width / toTransform.width;

    const squareSizeDiff =
        zoom * squareRatio * toTransform.width - toTransform.width;

    const transformX = offsetX + squareSizeDiff / 2;
    const transformY = offsetY + squareSizeDiff / 2;
    const transformScale = zoom * squareRatio;

    toTransform.style.transform = `
        matrix(
            ${transformScale}, 
            0, 0,
            ${transformScale},
            ${transformX}, ${transformY}
        )
    `;
}

let canvasFadingIn = false;
let canvasFadingOut = false;

async function canvasFadeIn() {
    const animationDuration = 1000; // 1 second
    const animationStartTime = performance.now();
    if (canvasFadingIn) {
        return;
    }
    canvasFadingIn = true;
    canvasFadingOut = false;
    const startingOpacity = Number(canvasLoadingAnimation.style.opacity);
    function animateOpacity() {
        const currentTime = performance.now();
        const elapsed = currentTime - animationStartTime;
        const opacity = Math.max(
            0,
            startingOpacity - elapsed / animationDuration
        );
        canvasLoadingAnimation.style.opacity = opacity;
        if (opacity > 0 && canvasFadingIn) {
            requestAnimationFrame(animateOpacity);
        } else {
            if (opacity === 0) {
                canvasLoadingAnimation.style.display = "none";
            }
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

    canvasFadingIn = false;
    canvasFadingOut = true;

    const startingOpacity = Number(canvasLoadingAnimation.style.opacity);

    if (startingOpacity === 0) {
        canvasLoadingAnimation.style.removeProperty("display");
    }

    function animateOpacity() {
        const currentTime = performance.now();
        const elapsed = currentTime - animationStartTime;

        const opacity = Math.min(
            1,
            startingOpacity + elapsed / animationDuration
        );

        canvasLoadingAnimation.style.opacity = opacity;

        if (opacity < 1 && canvasFadingOut) {
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
                    canvasWidth: canvasContainer.width,
                    canvasHeight: canvasContainer.height,
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

function renderLoopInit() {
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

    const stopZoom = () => {
        isMouseDown = false;
    };

    const pressedKeys = {};

    let clickZoomEnabled = clickZoomToggle.checked;

    canvasContainer.addEventListener("mouseup", stopZoom);

    canvasContainer.addEventListener("mousemove", setMousePosition);

    canvasContainer.addEventListener("touchend", (event) => {
        event.preventDefault();
        stopZoom();
    });

    canvasContainer.addEventListener("touchmove", (event) => {
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

    const loop = () => {
        if (!imageDirty) {
            // console.log("done rendering.");
            return;
        }

        imageDirty = false;

        const currentFrameTime = performance.now();
        const deltaTime = (currentFrameTime - lastFrameTime) / 1000; // Convert to seconds
        lastFrameTime = currentFrameTime;

        const zoomFactor = Math.pow(
            Math.pow(2, Math.pow(2, zoomRate)),
            deltaTime
        );

        if (workerInitialized) {
            if (!loading) {
                if (isMouseDown && clickZoomEnabled) {
                    worker.postMessage({
                        type: "zoomViewport",
                        mouseX: mouseX,
                        mouseY: mouseY,
                        zoomDelta: zoomFactor,
                    });
                    cachedPosition.updatePosition(mouseX, mouseY, zoomFactor);
                    oldCachedPosition.updatePosition(
                        mouseX,
                        mouseY,
                        zoomFactor
                    );
                    imageDirty = true;
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
                        offsetY -= canvasContainer.width * deltaTime;
                    }
                    if (pressedKeys["ArrowDown"]) {
                        offsetY += canvasContainer.width * deltaTime;
                    }
                    if (pressedKeys["ArrowLeft"]) {
                        offsetX -= canvasContainer.width * deltaTime;
                    }
                    if (pressedKeys["ArrowRight"]) {
                        offsetX += canvasContainer.width * deltaTime;
                    }

                    worker.postMessage({
                        type: "moveViewport",
                        offsetX,
                        offsetY,
                    });
                    cachedPosition.move(offsetX, offsetY);
                    oldCachedPosition.move(offsetX, offsetY);
                    imageDirty = true;
                }
            }

            pushImage();
        }

        requestAnimationFrame(loop);
    };

    const beginRenderLoop = () => {
        lastFrameTime = performance.now();

        // console.log("rendering...");

        requestAnimationFrame(loop);
    };

    const wake = () => {
        if (!imageDirty) {
            imageDirty = true;
            beginRenderLoop();
        }
    };

    canvasContainer.addEventListener("wheel", async (event) => {
        event.preventDefault();

        const scrollZoomFactor = Math.pow(
            Math.pow(2, Math.pow(2, scrollZoomRate)),
            0.1
        );

        worker.postMessage({
            type: "zoomViewport",
            mouseX: event.offsetX,
            mouseY: event.offsetY,
            zoomDelta:
                event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor,
        });
        cachedPosition.updatePosition(
            event.offsetX,
            event.offsetY,
            event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
        );
        oldCachedPosition.updatePosition(
            event.offsetX,
            event.offsetY,
            event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
        );

        wake();
    });

    document.addEventListener("keydown", (event) => {
        const arrowKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
        if (arrowKeys.includes(event.key)) {
            event.preventDefault();
            pressedKeys[event.key] = true;

            wake();
        }
    });

    document.addEventListener("keyup", (event) => {
        const arrowKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
        if (arrowKeys.includes(event.key)) {
            event.preventDefault();
            pressedKeys[event.key] = false;

            wake();
        }
    });

    async function handleMouseMoveDragging(event) {
        if ((event.buttons & 1) == 1 && !clickZoomEnabled) {
            worker.postMessage({
                type: "moveViewport",
                offsetX: event.movementX,
                offsetY: event.movementY,
            });
            cachedPosition.move(event.movementX, event.movementY);
            oldCachedPosition.move(event.movementX, event.movementY);

            wake();
        }
    }

    const startZoom = () => {
        isMouseDown = true;

        if (clickZoomEnabled) {
            wake();
        }
    };

    canvasContainer.addEventListener("touchstart", (event) => {
        event.preventDefault();
        startZoom();
        setTouchPosition(event);
    });

    clickZoomToggle.addEventListener("change", () => {
        clickZoomEnabled = clickZoomToggle.checked;

        if (clickZoomEnabled && isMouseDown) {
            wake();
        }
    });

    canvasContainer.addEventListener("mousedown", startZoom);
    canvasContainer.addEventListener("mousemove", handleMouseMoveDragging);

    return beginRenderLoop;
}

const renderLoop = renderLoopInit();
renderLoop();

function renderWake() {
    if (!imageDirty) {
        imageDirty = true;

        renderLoop();
    }
}

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
