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
        if (this.pointers.size < 2) return 1;
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
    constructor(element, friction = 0.99) {
        this.element = element;
        this.pointerManager = new PointerManager();

        this.friction = friction;
        this.dragVelocityX = 0;
        this.dragVelocityY = 0;
        this.scaleVelocity = 0;
        this.momentumActive = false;

        this.velocityHistory = [];

        // Bind event handlers
        this.handlePointerDown = this.handlePointerDown.bind(this);
        this.handlePointerMove = this.handlePointerMove.bind(this);
        this.handlePointerUp = this.handlePointerUp.bind(this);
        this.momentumTick = this.momentumTick.bind(this);

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
        this.stopMomentum();
    }

    handlePointerMove(event) {
        this.pointerManager.updatePointer(
            event.pointerId,
            event.clientX,
            event.clientY
        );

        const currentCentroid = this.pointerManager.calculateCentroid();
        const offsets = this.pointerManager.getOffsets(currentCentroid);
        const scale = Math.max(
            0.1,
            this.pointerManager.getScale(currentCentroid)
        );

        let totalDeltaX = 0;
        let totalDeltaY = 0;
        let totalDeltaScale = 0;

        if (
            (offsets.offsetX !== 0 || offsets.offsetY !== 0) &&
            currentCentroid
        ) {
            this.pointerManager.referenceCentroid = currentCentroid;

            totalDeltaX += offsets.offsetX;
            totalDeltaY += offsets.offsetY;
        }

        if (scale !== 1 && currentCentroid) {
            const deltaX = (currentCentroid.x || 0) * (1 - scale);
            const deltaY = (currentCentroid.y || 0) * (1 - scale);

            totalDeltaX += deltaX;
            totalDeltaY += deltaY;

            const zoomEvent = new CustomEvent("pointerzoom", {
                detail: {
                    scale,
                    offsetX: totalDeltaX / (1 - scale),
                    offsetY: totalDeltaY / (1 - scale),
                },
            });
            this.element.dispatchEvent(zoomEvent);

            totalDeltaScale += Math.log2(scale);
        } else {
            if (totalDeltaX !== 0 || totalDeltaY !== 0) {
                const dragEvent = new CustomEvent("pointerdrag", {
                    detail: { deltaX: totalDeltaX, deltaY: totalDeltaY },
                });

                this.element.dispatchEvent(dragEvent);
            }
        }

        const time = performance.now();
        this.velocityHistory.push({
            time,
            velX: totalDeltaX,
            velY: totalDeltaY,
            velScale: totalDeltaScale,
        });
    }

    handlePointerUp(event) {
        this.pointerManager.removePointer(event.pointerId);

        if (this.pointerManager.getPointerCount() === 0) {
            // Compute weighted average velocities from velocityHistory
            this.computeWeightedAverageVelocities();
            this.startMomentum();
        }
    }

    cleanVelocityHistory(currentTime) {
        while (
            this.velocityHistory.length > 0 &&
            currentTime - this.velocityHistory[0].time > 100
        ) {
            this.velocityHistory.shift();
        }
    }

    computeWeightedAverageVelocities() {
        const now = performance.now();
        this.cleanVelocityHistory(now);

        if (this.velocityHistory.length === 0) {
            this.dragVelocityX = 0;
            this.dragVelocityY = 0;
            this.scaleVelocity = 0;
            return;
        }

        let weightedX = 0;
        let weightedY = 0;
        let weightedScale = 0;

        for (let i = 0; i < this.velocityHistory.length; i++) {
            const current = this.velocityHistory[i];

            weightedX += current.velX;
            weightedY += current.velY;
            weightedScale += current.velScale;
        }

        const totalTime =
            (this.velocityHistory[this.velocityHistory.length - 1].time -
                this.velocityHistory[0].time) /
            1000;

        if (totalTime > 0) {
            this.dragVelocityX = weightedX / totalTime;
            this.dragVelocityY = weightedY / totalTime;
            this.scaleVelocity = weightedScale / totalTime;
        } else {
            this.dragVelocityX = 0;
            this.dragVelocityY = 0;
            this.scaleVelocity = 0;
        }
    }

    startMomentum() {
        if (this.momentumActive) return;
        this.momentumActive = true;
        this.lastTime = performance.now();
        requestAnimationFrame(this.momentumTick);
    }

    stopMomentum() {
        this.momentumActive = false;
    }

    momentumTick() {
        if (!this.momentumActive) return;

        const now = performance.now();
        const deltaTime = (now - this.lastTime) / 1000;

        if (deltaTime == 0) {
            requestAnimationFrame(this.momentumTick);
            return;
        }

        this.lastTime = now;

        const applyFriction = (v) => {
            const newV = v * this.friction ** (deltaTime * 1000);
            return Math.abs(newV) < 0.0001 ? 0 : newV;
        };

        this.dragVelocityX = applyFriction(this.dragVelocityX);
        this.dragVelocityY = applyFriction(this.dragVelocityY);
        this.scaleVelocity = applyFriction(this.scaleVelocity);

        let stillActive = false;

        if (this.scaleVelocity !== 0) {
            const scaleChange = 2 ** (this.scaleVelocity * deltaTime);

            const deltaX = this.dragVelocityX * deltaTime;
            const deltaY = this.dragVelocityY * deltaTime;

            const zoomEvent = new CustomEvent("pointerzoom", {
                detail: {
                    scale: scaleChange,
                    offsetX: deltaX / (1 - scaleChange),
                    offsetY: deltaY / (1 - scaleChange),
                },
            });
            this.element.dispatchEvent(zoomEvent);
            stillActive = true;
        } else if (this.dragVelocityX !== 0 || this.dragVelocityY !== 0) {
            const deltaX = this.dragVelocityX * deltaTime;
            const deltaY = this.dragVelocityY * deltaTime;

            const dragEvent = new CustomEvent("pointerdrag", {
                detail: { deltaX, deltaY },
            });
            this.element.dispatchEvent(dragEvent);
            stillActive = true;
        }

        if (stillActive) {
            requestAnimationFrame(this.momentumTick);
        } else {
            this.momentumActive = false;
        }
    }

    destroy() {
        this.element.removeEventListener("pointerdown", this.handlePointerDown);
        this.element.removeEventListener("pointermove", this.handlePointerMove);
        this.element.removeEventListener("pointerup", this.handlePointerUp);
        this.element.removeEventListener("pointercancel", this.handlePointerUp);
        this.stopMomentum();
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

        const canvasSquareSize = Math.max(clientWidth, clientHeight);

        canvasContainer.width = clientWidth;
        canvasContainer.height = clientHeight;

        if (clientWidth > clientHeight) {
            canvasContainer.offsetX = 0;
            canvasContainer.offsetY = (clientWidth - clientHeight) / 2;
        } else {
            canvasContainer.offsetX = (clientHeight - clientWidth) / 2;
            canvasContainer.offsetY = 0;
        }

        canvasContainer.squareSize = canvasSquareSize;

        // renderImageFromCache();

        cachedPosition.updateDimensions(canvasSquareSize, canvasSquareSize);
        oldCachedPosition.updateDimensions(canvasSquareSize, canvasSquareSize);

        renderWake();

        if (workerInitialized) {
            worker.postMessage({
                type: "resizeViewport",
                canvasWidth: canvasSquareSize,
                canvasHeight: canvasSquareSize,
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
            canvasContainer.squareSize,
            canvasContainer.squareSize
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
            canvasContainer.squareSize,
            canvasContainer.squareSize
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

    offsetX = cachedPosition.offsetX - canvasContainer.offsetX;
    offsetY = cachedPosition.offsetY - canvasContainer.offsetY;
    zoom = cachedPosition.zoom;

    oldOffsetX = oldCachedPosition.offsetX - canvasContainer.offsetX;
    oldOffsetY = oldCachedPosition.offsetY - canvasContainer.offsetY;
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
    const squareRatio = canvasContainer.squareSize / toTransform.width;

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
                    canvasWidth: canvasContainer.squareSize,
                    canvasHeight: canvasContainer.squareSize,
                });
            });

            await new Promise((resolve) => {
                const handleWorkerMessage = (e) => {
                    if (e.data.type === "zoomViewportComplete") {
                        worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        resolve();
                    }
                };

                const mouseX = canvasContainer.width / 2;
                const mouseY = canvasContainer.height / 2;

                const zoomFactor =
                    (Math.min(canvasContainer.width, canvasContainer.height) /
                        canvasContainer.squareSize) *
                    0.8;

                worker.addEventListener("message", handleWorkerMessage);
                worker.postMessage({
                    type: "zoomViewport",
                    mouseX: mouseX + canvasContainer.offsetX,
                    mouseY: mouseY + canvasContainer.offsetY,
                    zoomDelta: zoomFactor,
                });

                cachedPosition.updatePosition(
                    mouseX + canvasContainer.offsetX,
                    mouseY + canvasContainer.offsetY,
                    zoomFactor
                );
                oldCachedPosition.updatePosition(
                    mouseX + canvasContainer.offsetX,
                    mouseY + canvasContainer.offsetY,
                    zoomFactor
                );
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
                        mouseX: mouseX + canvasContainer.offsetX,
                        mouseY: mouseY + canvasContainer.offsetY,
                        zoomDelta: zoomFactor,
                    });
                    cachedPosition.updatePosition(
                        mouseX + canvasContainer.offsetX,
                        mouseY + canvasContainer.offsetY,
                        zoomFactor
                    );
                    oldCachedPosition.updatePosition(
                        mouseX + canvasContainer.offsetX,
                        mouseY + canvasContainer.offsetY,
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
                        offsetY -= canvasContainer.squareSize * deltaTime;
                    }
                    if (pressedKeys["ArrowDown"]) {
                        offsetY += canvasContainer.squareSize * deltaTime;
                    }
                    if (pressedKeys["ArrowLeft"]) {
                        offsetX -= canvasContainer.squareSize * deltaTime;
                    }
                    if (pressedKeys["ArrowRight"]) {
                        offsetX += canvasContainer.squareSize * deltaTime;
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
            mouseX: event.offsetX + canvasContainer.offsetX,
            mouseY: event.offsetY + canvasContainer.offsetY,
            zoomDelta:
                event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor,
        });
        cachedPosition.updatePosition(
            event.offsetX + canvasContainer.offsetX,
            event.offsetY + canvasContainer.offsetY,
            event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
        );
        oldCachedPosition.updatePosition(
            event.offsetX + canvasContainer.offsetX,
            event.offsetY + canvasContainer.offsetY,
            event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
        );

        wake();
    });

    canvasContainer.addEventListener("pointerzoom", (event) => {
        event.preventDefault();

        event = event.detail;

        const scrollZoomFactor = event.scale;

        worker.postMessage({
            type: "zoomViewport",
            mouseX: event.offsetX + canvasContainer.offsetX,
            mouseY: event.offsetY + canvasContainer.offsetY,
            zoomDelta: scrollZoomFactor,
        });
        cachedPosition.updatePosition(
            event.offsetX + canvasContainer.offsetX,
            event.offsetY + canvasContainer.offsetY,
            scrollZoomFactor
        );
        oldCachedPosition.updatePosition(
            event.offsetX + canvasContainer.offsetX,
            event.offsetY + canvasContainer.offsetY,
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

    function handlePointerDrag(event) {
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
