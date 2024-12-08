"use strict";

class PointerManager {
    constructor() {
        this.pointers = new Map();
        this.referenceCentroid = null;
        this.lastAverageDistance = null;
    }

    addPointer(id, x, y) {
        this.pointers.set(id, { x, y });
        this.updateReferenceCentroid();
    }

    updatePointer(id, x, y) {
        if (this.pointers.has(id)) {
            this.pointers.set(id, { x, y });
        }
    }

    removePointer(id) {
        this.pointers.delete(id);
        this.updateReferenceCentroid();
    }

    getPointerCount() {
        return this.pointers.size;
    }

    calculateCentroid() {
        const points = Array.from(this.pointers.values());
        const total = points.reduce(
            (acc, point) => {
                acc.x += point.x;
                acc.y += point.y;
                return acc;
            },
            { x: 0, y: 0 }
        );
        return points.length > 0
            ? { x: total.x / points.length, y: total.y / points.length }
            : null;
    }

    calculateAverageDistance(centroid) {
        if (!centroid) return 0;
        const points = Array.from(this.pointers.values());
        const totalDistance = points.reduce((acc, point) => {
            const deltaX = point.x - centroid.x;
            const deltaY = point.y - centroid.y;
            return acc + Math.sqrt(deltaX ** 2 + deltaY ** 2);
        }, 0);
        return points.length > 0 ? totalDistance / points.length : 0;
    }

    updateReferenceCentroid() {
        const newCentroid = this.calculateCentroid();
        if (this.referenceCentroid && newCentroid) {
            const offsetX = newCentroid.x - this.referenceCentroid.x;
            const offsetY = newCentroid.y - this.referenceCentroid.y;
            this.referenceCentroid.x += offsetX;
            this.referenceCentroid.y += offsetY;
        } else {
            this.referenceCentroid = newCentroid;
        }
        this.lastAverageDistance = this.calculateAverageDistance(
            this.referenceCentroid
        );
    }

    getOffsets(newCentroid) {
        if (!this.referenceCentroid || !newCentroid)
            return { offsetX: 0, offsetY: 0 };
        return {
            offsetX: newCentroid.x - this.referenceCentroid.x,
            offsetY: newCentroid.y - this.referenceCentroid.y,
        };
    }

    getScale(newCentroid) {
        if (this.pointers.size < 2) return 1; // Return scale of 1 if there is only one pointer
        const currentAverageDistance =
            this.calculateAverageDistance(newCentroid);
        const scale =
            currentAverageDistance /
            (this.lastAverageDistance || currentAverageDistance);
        this.lastAverageDistance = currentAverageDistance;
        return scale;
    }
}

class PointerHandler {
    constructor(element) {
        this.element = element;
        this.pointerManager = new PointerManager();

        // Bind event handlers
        this.handlePointerDown = this.handlePointerDown.bind(this);
        this.handlePointerMove = this.handlePointerMove.bind(this);
        this.handlePointerUp = this.handlePointerUp.bind(this);

        // Add event listeners
        this.element.addEventListener("pointerdown", this.handlePointerDown);
        this.element.addEventListener("pointermove", this.handlePointerMove);
        this.element.addEventListener("pointerup", this.handlePointerUp);
        this.element.addEventListener("pointercancel", this.handlePointerUp);
    }

    handlePointerDown(event) {
        this.pointerManager.addPointer(
            event.pointerId,
            event.clientX,
            event.clientY
        );
    }

    handlePointerMove(event) {
        this.pointerManager.updatePointer(
            event.pointerId,
            event.clientX,
            event.clientY
        );

        const currentCentroid = this.pointerManager.calculateCentroid();
        const offsets = this.pointerManager.getOffsets(currentCentroid);

        if (offsets.offsetX !== 0 || offsets.offsetY !== 0) {
            this.pointerManager.referenceCentroid = currentCentroid;

            const dragEvent = new CustomEvent("pointerdrag", {
                detail: { deltaX: offsets.offsetX, deltaY: offsets.offsetY },
            });
            this.element.dispatchEvent(dragEvent);
        }

        const scale = Math.max(
            0.1,
            this.pointerManager.getScale(currentCentroid)
        );

        if (scale !== 1) {
            const zoomEvent = new CustomEvent("pointerzoom", {
                detail: {
                    scale,
                    offsetX: currentCentroid?.x || 0,
                    offsetY: currentCentroid?.y || 0,
                },
            });
            this.element.dispatchEvent(zoomEvent);
        }
    }

    handlePointerUp(event) {
        this.pointerManager.removePointer(event.pointerId);

        if (this.pointerManager.getPointerCount() === 0) {
            // Reset state when all pointers are lifted
            this.pointerManager.referenceCentroid = null;
            this.pointerManager.lastAverageDistance = null;
        }
    }

    destroy() {
        this.element.removeEventListener("pointerdown", this.handlePointerDown);
        this.element.removeEventListener("pointermove", this.handlePointerMove);
        this.element.removeEventListener("pointerup", this.handlePointerUp);
        this.element.removeEventListener("pointercancel", this.handlePointerUp);
    }
}

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

function testGestures(element) {
    if (!(element instanceof HTMLElement)) {
        throw new Error("Provided input is not a valid DOM element.");
    }

    const rect = element.getBoundingClientRect();

    // Normalize coordinates to element size
    function normalizeToElement(x, y) {
        return {
            clientX: rect.left + x * rect.width,
            clientY: rect.top + y * rect.height,
        };
    }

    // Pointer visual management
    const pointerVisuals = {};

    function createPointerVisual(pointerId, x, y) {
        const visual = document.createElement("div");
        visual.style.position = "absolute";
        visual.style.width = "30px";
        visual.style.height = "30px";
        visual.style.background = `conic-gradient(from 0deg, #FFD700, #FFA500, #FFD700)`;
        visual.style.borderRadius = "50%";
        visual.style.boxShadow = "0 0 10px rgba(255, 223, 0, 0.6)";
        visual.style.animation =
            "spin 1s linear infinite, pulse-shadow 1s infinite";
        visual.style.pointerEvents = "none";
        visual.style.zIndex = "999999";
        visual.style.left = `${x - 15}px`;
        visual.style.top = `${y - 15}px`;
        document.body.appendChild(visual);
        pointerVisuals[pointerId] = visual;

        const style = document.createElement("style");
        style.textContent = `
            @keyframes spin {
                0% { transform: rotate(0deg); }
                100% { transform: rotate(360deg); }
            }
            @keyframes pulse-shadow {
                0% { box-shadow: 0 0 10px rgba(255, 223, 0, 0.6); }
                50% { box-shadow: 0 0 20px rgba(255, 223, 0, 1); }
                100% { box-shadow: 0 0 10px rgba(255, 223, 0, 0.6); }
            }
        `;
        document.head.appendChild(style);
    }

    function movePointerVisual(pointerId, x, y) {
        const visual = pointerVisuals[pointerId];
        if (visual) {
            visual.style.left = `${x - 15}px`;
            visual.style.top = `${y - 15}px`;
        }
    }

    function removePointerVisual(pointerId) {
        const visual = pointerVisuals[pointerId];
        if (visual) {
            visual.remove();
            delete pointerVisuals[pointerId];
        }
    }

    function triggerPointerEvent(type, { pointerId, x, y }, target = element) {
        const { clientX, clientY } = normalizeToElement(x, y);

        const event = new PointerEvent(type, {
            pointerId,
            bubbles: true,
            cancelable: true,
            clientX,
            clientY,
            isPrimary: pointerId === 1,
            pointerType: "touch",
        });
        target.dispatchEvent(event);

        if (type === "pointerdown") {
            createPointerVisual(pointerId, clientX, clientY);
        } else if (type === "pointermove") {
            movePointerVisual(pointerId, clientX, clientY);
        } else if (type === "pointerup" || type === "pointercancel") {
            removePointerVisual(pointerId);
        }
    }

    function delay(ms) {
        return new Promise((resolve) => setTimeout(resolve, ms));
    }

    async function gesture(startPoints, endPoints, steps = 30, duration = 500) {
        const interval = duration / steps;
        const pointers = Object.keys(startPoints);

        pointers.forEach((pointerId) => {
            triggerPointerEvent("pointerdown", {
                pointerId: parseInt(pointerId, 10),
                ...startPoints[pointerId],
            });
        });

        for (let i = 1; i <= steps; i++) {
            const progress = i / steps;
            pointers.forEach((pointerId) => {
                const start = startPoints[pointerId];
                const end = endPoints[pointerId];
                const currentX = start.x + (end.x - start.x) * progress;
                const currentY = start.y + (end.y - start.y) * progress;
                triggerPointerEvent("pointermove", {
                    pointerId: parseInt(pointerId, 10),
                    x: currentX,
                    y: currentY,
                });
            });
            await delay(interval);
        }

        pointers.forEach((pointerId) => {
            triggerPointerEvent("pointerup", {
                pointerId: parseInt(pointerId, 10),
                ...endPoints[pointerId],
            });
        });
    }

    async function singleFingerDrag() {
        console.log("Testing single finger drag...");
        await gesture({ 1: { x: 0.1, y: 0.1 } }, { 1: { x: 0.9, y: 0.9 } });
    }

    async function twoFingerPinch() {
        console.log("Testing two-finger pinch...");
        await gesture(
            {
                1: { x: 0.3, y: 0.5 },
                2: { x: 0.7, y: 0.5 },
            },
            {
                1: { x: 0.4, y: 0.5 },
                2: { x: 0.6, y: 0.5 },
            }
        );
    }

    async function fourFingerZoom() {
        console.log("Testing four-finger zoom...");
        await gesture(
            {
                1: { x: 0.2, y: 0.4 },
                2: { x: 0.8, y: 0.4 },
                3: { x: 0.2, y: 0.6 },
                4: { x: 0.8, y: 0.6 },
            },
            {
                1: { x: 0.4, y: 0.5 },
                2: { x: 0.6, y: 0.5 },
                3: { x: 0.4, y: 0.5 },
                4: { x: 0.6, y: 0.5 },
            }
        );
    }

    async function threeToTwoToOneFingerGesture() {
        console.log("Testing three-to-two-to-one finger gesture...");
        await gesture(
            {
                1: { x: 0.2, y: 0.2 },
                2: { x: 0.5, y: 0.2 },
                3: { x: 0.8, y: 0.2 },
            },
            {
                1: { x: 0.4, y: 0.5 },
                2: { x: 0.5, y: 0.5 },
                3: { x: 0.6, y: 0.5 },
            }
        );

        await delay(200);

        await gesture(
            {
                1: { x: 0.4, y: 0.5 },
                2: { x: 0.6, y: 0.5 },
            },
            {
                1: { x: 0.5, y: 0.5 },
                2: { x: 0.5, y: 0.5 },
            }
        );

        await delay(200);

        await gesture(
            {
                1: { x: 0.5, y: 0.5 },
            },
            {
                1: { x: 0.9, y: 0.9 },
            }
        );
    }

    // Execute all gestures
    (async () => {
        // await singleFingerDrag();
        await twoFingerPinch();
        // await fourFingerZoom();
        // await threeToTwoToOneFingerGesture();
    })();
}

// document.addEventListener("keydown", function (event) {
//     if (event.code === "Space") {
//         testGestures(canvasContainer);
//     }
// });

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

const pointerHandler = new PointerHandler(canvasContainer);

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

    canvasContainer.addEventListener("pointerdrag", handlePointerDrag);

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

    canvasContainer.addEventListener("pointerzoom", async (event) => {
        event.preventDefault();

        event = event.detail;

        const scrollZoomFactor = event.scale;

        worker.postMessage({
            type: "zoomViewport",
            mouseX: event.offsetX,
            mouseY: event.offsetY,
            zoomDelta: scrollZoomFactor,
        });
        cachedPosition.updatePosition(
            event.offsetX,
            event.offsetY,
            scrollZoomFactor
        );
        oldCachedPosition.updatePosition(
            event.offsetX,
            event.offsetY,
            scrollZoomFactor
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

    async function handlePointerDrag(event) {
        event = event.detail;
        if (!clickZoomEnabled) {
            worker.postMessage({
                type: "moveViewport",
                offsetX: event.deltaX,
                offsetY: event.deltaY,
            });
            cachedPosition.move(event.deltaX, event.deltaY);
            oldCachedPosition.move(event.deltaX, event.deltaY);

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
