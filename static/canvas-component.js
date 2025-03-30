"use strict";

/**
 * @typedef {Object} Point
 * @property {number} x
 * @property {number} y
 */

/**
 * @typedef {Object} OffsetInfo
 * @property {number} offsetX
 * @property {number} offsetY
 */

/**
 * @typedef {Object} VelocityEntry
 * @property {number} time
 * @property {number} velX
 * @property {number} velY
 * @property {number} velScale
 */

/**
 * Manages pointer positions and calculates centroid and scale changes
 */
class PointerManager {
    /** @type {Map<number, Point>} */
    pointers;

    /** @type {Point|null} */
    referenceCentroid;

    /** @type {number|null} */
    lastAverageDistance;

    constructor() {
        this.pointers = new Map();
        this.referenceCentroid = null;
        this.lastAverageDistance = null;
    }

    /**
     * @param {number} id
     * @param {number} x
     * @param {number} y
     */
    addPointer(id, x, y) {
        this.pointers.set(id, { x, y });
        this.updateReferenceCentroid();
    }

    /**
     * @param {number} id
     * @param {number} x
     * @param {number} y
     */
    updatePointer(id, x, y) {
        if (this.pointers.has(id)) {
            this.pointers.set(id, { x, y });
        }
    }

    /**
     * @param {number} id
     */
    removePointer(id) {
        this.pointers.delete(id);
        this.updateReferenceCentroid();
    }

    /**
     * @returns {number}
     */
    getPointerCount() {
        return this.pointers.size;
    }

    /**
     * @returns {Point|null}
     */
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

    /**
     * @param {Point|null} centroid
     * @returns {number}
     */
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

    /**
     * Updates the reference centroid based on current pointer positions
     */
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

    /**
     * @param {Point|null} newCentroid
     * @returns {OffsetInfo}
     */
    getOffsets(newCentroid) {
        if (!this.referenceCentroid || !newCentroid)
            return { offsetX: 0, offsetY: 0 };
        return {
            offsetX: newCentroid.x - this.referenceCentroid.x,
            offsetY: newCentroid.y - this.referenceCentroid.y,
        };
    }

    /**
     * @param {Point|null} newCentroid
     * @returns {number}
     */
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

/**
 * Handles pointer events and momentum calculations for drag and zoom operations
 */
class PointerHandler {
    /** @type {HTMLElement} */
    element;

    /** @type {PointerManager} */
    pointerManager;

    /** @type {number} */
    friction;

    /** @type {number} */
    dragVelocityX;

    /** @type {number} */
    dragVelocityY;

    /** @type {number} */
    scaleVelocity;

    /** @type {boolean} */
    momentumActive;

    /** @type {VelocityEntry[]} */
    velocityHistory;

    /** @type {number} */
    lastTime;

    /**
     * @param {HTMLElement} element
     * @param {number} [friction=0.99]
     */
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

    /**
     * @param {PointerEvent} event
     */
    handlePointerDown(event) {
        this.pointerManager.addPointer(
            event.pointerId,
            event.offsetX,
            event.offsetY
        );
        this.stopMomentum();
    }

    /**
     * @param {PointerEvent} event
     */
    handlePointerMove(event) {
        this.pointerManager.updatePointer(
            event.pointerId,
            event.offsetX,
            event.offsetY
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

    /**
     * @param {PointerEvent} event
     */
    handlePointerUp(event) {
        this.pointerManager.removePointer(event.pointerId);

        if (this.pointerManager.getPointerCount() === 0) {
            // Compute weighted average velocities from velocityHistory
            this.computeWeightedAverageVelocities();
            this.startMomentum();
        }
    }

    /**
     * @param {number} currentTime
     */
    cleanVelocityHistory(currentTime) {
        while (
            this.velocityHistory.length > 0 &&
            currentTime - this.velocityHistory[0].time > 100
        ) {
            this.velocityHistory.shift();
        }
    }

    /**
     * Computes weighted average velocities from the velocity history
     */
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

    /**
     * Starts the momentum animation
     */
    startMomentum() {
        if (this.momentumActive) return;
        this.momentumActive = true;
        this.lastTime = performance.now();
        requestAnimationFrame(this.momentumTick);
    }

    /**
     * Stops the momentum animation
     */
    stopMomentum() {
        this.momentumActive = false;
    }

    /**
     * Animation frame callback for momentum
     */
    momentumTick() {
        if (!this.momentumActive) return;

        const now = performance.now();
        const deltaTime = (now - this.lastTime) / 1000;

        if (deltaTime == 0) {
            requestAnimationFrame(this.momentumTick);
            return;
        }

        this.lastTime = now;

        /**
         * @param {number} v
         * @returns {number}
         */
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

    /**
     * Cleans up all event listeners and stops momentum
     */
    destroy() {
        this.element.removeEventListener("pointerdown", this.handlePointerDown);
        this.element.removeEventListener("pointermove", this.handlePointerMove);
        this.element.removeEventListener("pointerup", this.handlePointerUp);
        this.element.removeEventListener("pointercancel", this.handlePointerUp);
        this.stopMomentum();
    }
}

/**
 * Manages client-side position and zoom state
 */
class ClientPosition {
    /** @type {number} */
    zoom;

    /** @type {number} */
    offsetX;

    /** @type {number} */
    offsetY;

    /** @type {number} */
    canvasWidth;

    /** @type {number} */
    canvasHeight;

    /**
     * @param {number} zoom
     * @param {number} offsetX
     * @param {number} offsetY
     * @param {number} canvasWidth
     * @param {number} canvasHeight
     */
    constructor(zoom, offsetX, offsetY, canvasWidth, canvasHeight) {
        this.zoom = zoom;
        this.offsetX = offsetX;
        this.offsetY = offsetY;
        this.canvasWidth = canvasWidth;
        this.canvasHeight = canvasHeight;
    }

    /**
     * @param {number} mouseX
     * @param {number} mouseY
     * @param {number} zoomDelta
     */
    updatePosition(mouseX, mouseY, zoomDelta) {
        this.zoom *= zoomDelta;
        this.offsetX = mouseX - (mouseX - this.offsetX) * zoomDelta;
        this.offsetY = mouseY - (mouseY - this.offsetY) * zoomDelta;
    }

    /**
     * @param {number} offsetX
     * @param {number} offsetY
     */
    move(offsetX, offsetY) {
        this.offsetX += offsetX;
        this.offsetY += offsetY;
    }

    /**
     * @param {number} canvasWidth
     * @param {number} canvasHeight
     */
    updateDimensions(canvasWidth, canvasHeight) {
        if (
            this.canvasWidth === canvasWidth &&
            this.canvasHeight === canvasHeight
        ) {
            return;
        }

        // Convert current offsets to relative positions (0-1)
        const relativeX = this.offsetX / this.canvasWidth;
        const relativeY = this.offsetY / this.canvasHeight;

        // Update dimensions
        this.canvasWidth = canvasWidth;
        this.canvasHeight = canvasHeight;

        // Convert back to absolute positions with new dimensions
        this.offsetX = relativeX * this.canvasWidth;
        this.offsetY = relativeY * this.canvasHeight;
    }
}

/**
 * @typedef {Object} PushCacheData
 * @property {ImageBitmap|null} data
 * @property {number} clipX
 * @property {number} clipY
 * @property {number} clipWidth
 * @property {number} clipHeight
 */

/**
 * Displays a canvas with pan and zoom capabilities
 * @extends HTMLElement
 */
class CanvasComponent extends HTMLElement {
    // Public properties
    /** @type {number} */
    clickZoomRate = 1;

    /** @type {number} */
    scrollZoomRate = 1;

    /** @type {boolean} */
    clickZoom = false;

    // Private fields
    /** @type {Worker|null} */
    #worker = null;

    /** @type {PointerHandler|null} */
    #pointerHandler = null;

    /** @type {ResizeObserver|null} */
    #resizeObserver = null;

    /** @type {ClientPosition|null} */
    #cachedPosition = {
        zoom: 1,
        offsetX: 0,
        offsetY: 0,
        canvasWidth: 1,
        canvasHeight: 1,
    };

    /** @type {boolean} */
    #initializedWorkerPosition = false;

    /** @type {PushCacheData|null} */
    #pushCache = null;

    /** @type {boolean} */
    #loading = true;

    /** @type {boolean} */
    #imageDirty = true;

    /** @type {boolean} */
    #workerInitialized = false;

    /** @type {boolean} */
    #canvasFadingIn = false;

    /** @type {boolean} */
    #canvasFadingOut = false;

    /** @type {Object.<string, boolean>} */
    #pressedKeys = {};

    /** @type {HTMLCanvasElement|null} */
    #displayCanvas = null;

    /** @type {ImageBitmapRenderingContext|null} */
    #displayCtx = null;

    /** @type {HTMLDivElement|null} */
    #displayCanvasParent = null;

    /** @type {number} */
    #displayCanvasBaseScale = 1;

    /** @type {HTMLDivElement|null} */
    #canvasLoadingAnimation = null;

    /** @type {Function|null} */
    #renderLoop = null;

    /** @type {boolean} */
    #isMouseDown = false;

    /** @type {number} */
    #mouseX = 0;

    /** @type {number} */
    #mouseY = 0;

    /** @type {number} */
    #lastMouseDownTime = 0;

    /** @type {Object.<string, number>} */
    #keyPressStartTimes = {};

    /** @type {number} */
    #positionVersion = 0n;

    /** @type {boolean} */
    #hasError = false;

    /** @type {HTMLDivElement|null} */
    #errorMessageElement = null;

    constructor() {
        super();

        try {
            // Create shadow DOM
            this.attachShadow({ mode: "open" });

            // Initialize position with actual width and height
            const rect = this.getBoundingClientRect();
            this.#cachedPosition = new ClientPosition(
                1,
                0,
                0,
                rect.width || 1,
                rect.height || 1
            );
        } catch (error) {
            console.error("Error in CanvasComponent constructor:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * Lifecycle callback when element is added to the DOM
     */
    connectedCallback() {
        try {
            // Initialize the component
            this.#initializeComponent();
            this.#setupEventListeners();
            this.#initializeWorker();
            this.#startRenderLoop();
        } catch (error) {
            console.error("Error in connectedCallback:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * Lifecycle callback when element is removed from the DOM
     */
    disconnectedCallback() {
        try {
            // Clean up resources
            this.#cleanupResources();
        } catch (error) {
            console.error("Error in disconnectedCallback:", error);
        }
    }

    /**
     * @returns {string[]}
     */
    static get observedAttributes() {
        return ["click-zoom-rate", "scroll-zoom-rate", "click-zoom"];
    }

    /**
     * @param {string} name
     * @param {string} oldValue
     * @param {string} newValue
     */
    attributeChangedCallback(name, oldValue, newValue) {
        try {
            switch (name) {
                case "click-zoom-rate":
                    this.clickZoomRate = Number(newValue) || 1;
                    break;
                case "scroll-zoom-rate":
                    this.scrollZoomRate = Number(newValue) || 1;
                    break;
                case "click-zoom":
                    this.clickZoom = newValue !== null;
                    break;
            }
        } catch (error) {
            console.error("Error in attributeChangedCallback:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * Shows an error message when something goes wrong
     * @private
     */
    #showErrorMessage() {
        if (this.#hasError) return; // Prevent showing multiple error messages

        this.#hasError = true;

        // Clean up resources first
        this.#cleanupResources();

        // Clear the shadow DOM
        if (this.shadowRoot) {
            this.shadowRoot.innerHTML = "";

            // Create and style the error message
            this.#errorMessageElement = document.createElement("div");
            this.#errorMessageElement.textContent =
                "Something went wrong, please refresh.";
            this.#errorMessageElement.style.cssText = `
                display: flex;
                justify-content: center;
                align-items: center;
                width: 100%;
                height: 100%;
                color: #ff3333;
                background-color: #f8f8f8;
                text-align: center;
                box-sizing: border-box;
            `;

            this.shadowRoot.appendChild(this.#errorMessageElement);
        }
    }

    #initializeComponent() {
        try {
            CSS.registerProperty({
                name: "--canvas-component-inverse-waterdrop-percent",
                syntax: "<percentage>",
                inherits: false,
                initialValue: "40%",
            });
        } catch (e) {
            if (e.name !== "InvalidModificationError") {
                throw e;
            }
        }

        this.shadowRoot.innerHTML = /*html*/ `
        <style>
            :host {
                --bg-primary: #eeeeee;
                --bg-secondary: #f5f5f5;
            }

            @media (prefers-color-scheme: dark) {
                :host {
                    --bg-primary: rgb(34, 34, 34);
                    --bg-secondary: rgb(38, 38, 38);
                }
            }

            :host {
                position: relative;
                overflow: clip;
                display: block;
                width: 30rem;
                height: 30rem;
                background: repeating-linear-gradient(45deg, var(--bg-primary), var(--bg-primary) 2.5%, var(--bg-secondary) 2.5%, var(--bg-secondary) 5%);
            }

            #display-canvas {
                pointer-events: none;
                z-index: 0;
            }

            #canvas-parent {
                will-change: transform;
                top: 0;
                left: 0;
                position: absolute;
                pointer-events: none;
                z-index: 0;
                transform-origin: top left;
                backface-visibility: hidden;
            }

            @keyframes inverse-waterdrop {
                0% {
                --canvas-component-inverse-waterdrop-percent: 40%;
                }
                100% {
                --canvas-component-inverse-waterdrop-percent: 0%;
                }
            }

            #canvas-loading {
                z-index: 1;
                position: relative;
                pointer-events: none;
                width: 100%;
                height: 100%;
                --percent-a: var(--canvas-component-inverse-waterdrop-percent);
                --percent-b: calc(var(--percent-a) + 20%);
                --percent-c: calc(var(--percent-b) + 20%);
                background: repeating-radial-gradient(circle, #eee var(--percent-a), #9c9c9c var(--percent-b), #eee var(--percent-c));
                animation: inverse-waterdrop 1s linear infinite;
            }
        </style>
        <div id="canvas-parent">
            <canvas id="display-canvas"></canvas>
        </div>
        <div id="canvas-loading"></div>
        `;

        // Get DOM references
        this.#displayCanvas = this.shadowRoot.getElementById("display-canvas");
        this.#displayCanvas.width = 2048;
        this.#displayCanvas.height = 2048;
        this.#displayCtx = this.#displayCanvas.getContext("bitmaprenderer");

        this.#displayCanvasParent =
            this.shadowRoot.getElementById("canvas-parent");

        this.#canvasLoadingAnimation =
            this.shadowRoot.getElementById("canvas-loading");
        this.#canvasLoadingAnimation.style.opacity = 1;

        // Initialize pointer handler
        this.#pointerHandler = new PointerHandler(this);
    }

    #setupEventListeners() {
        try {
            // Set up ResizeObserver
            this.#resizeObserver = new ResizeObserver((entries) => {
                try {
                    for (const entry of entries) {
                        const { clientWidth, clientHeight } = entry.target;
                        this.#handleResize(clientWidth, clientHeight);
                    }
                } catch (error) {
                    console.error("Error in ResizeObserver callback:", error);
                    this.#showErrorMessage();
                }
            });

            // Observe the component
            this.#resizeObserver.observe(this);

            // Wheel event for zooming
            this.addEventListener("wheel", this.#handleWheel.bind(this), {
                passive: false,
            });

            // Pointer events
            this.addEventListener(
                "pointerdrag",
                this.#handlePointerDrag.bind(this)
            );
            this.addEventListener(
                "pointerzoom",
                this.#handlePointerZoom.bind(this)
            );

            // Mouse events
            this.addEventListener(
                "mousedown",
                this.#handleMouseDown.bind(this)
            );
            this.addEventListener("mouseup", this.#handleMouseUp.bind(this));
            this.addEventListener(
                "mousemove",
                this.#handleMouseMove.bind(this)
            );

            // Touch events
            this.addEventListener(
                "touchstart",
                this.#handleTouchStart.bind(this),
                {
                    passive: false,
                }
            );
            this.addEventListener("touchend", this.#handleTouchEnd.bind(this));
            this.addEventListener(
                "touchmove",
                this.#handleTouchMove.bind(this),
                {
                    passive: false,
                }
            );

            // Keyboard events
            document.addEventListener(
                "keydown",
                this.#handleKeyDown.bind(this)
            );
            document.addEventListener("keyup", this.#handleKeyUp.bind(this));
        } catch (error) {
            console.error("Error in setupEventListeners:", error);
            this.#showErrorMessage();
        }
    }

    #initializeWorker() {
        try {
            this.#worker = new Worker("wasm-worker.js");

            this.#worker.onmessage = async (e) => {
                try {
                    const {
                        type,
                        fileUrl,
                        data,
                        offsetX,
                        offsetY,
                        zoom,
                        clipX,
                        clipY,
                        clipWidth,
                        clipHeight,
                        maxDetail,
                        version,
                        imageUrl,
                    } = e.data;

                    switch (type) {
                        case "initComplete": {
                            await this.#handleWorkerInitComplete();
                            break;
                        }
                        case "setOffsetComplete":
                            break;
                        case "saveOffsetComplete": {
                            const downloadLink = document.createElement("a");
                            downloadLink.href = fileUrl;
                            downloadLink.download = "position.bin";
                            downloadLink.click();
                            break;
                        }
                        case "renderImage": {
                            if (!this.#pushCache) {
                                this.#pushCache = {};
                            }

                            if (data) {
                                if (this.#pushCache.data) {
                                    this.#pushCache.data.close();
                                }

                                this.#pushCache = {
                                    data,
                                    clipX,
                                    clipY,
                                    clipWidth,
                                    clipHeight,
                                };

                                this.#cachedPosition = new ClientPosition(
                                    zoom,
                                    offsetX,
                                    offsetY,
                                    this.width || 1,
                                    this.height || 1
                                );

                                this.#positionVersion = version;

                                if ((Number(version) & 1) == 1) {
                                    this.#updateWorkerPosition();
                                }

                                {
                                    const toTransform = data;

                                    let effectiveToTransformWidth =
                                        toTransform.width;
                                    let effectiveToTransformHeight =
                                        toTransform.height;

                                    let scaleX =
                                        this.width / effectiveToTransformWidth;

                                    this.#displayCanvasBaseScale = scaleX;
                                }
                            }

                            this.#renderWake();
                            break;
                        }
                        case "makeImageComplete": {
                            const downloadLink = document.createElement("a");
                            downloadLink.href = imageUrl;
                            downloadLink.download = "image.png";
                            downloadLink.click();
                            break;
                        }
                        case "zoomViewportComplete":
                        case "moveViewportComplete":
                        case "resizeViewportComplete":
                        case "findImageComplete":
                        case "updatePositionComplete":
                        case "resetPositionComplete":
                            break;
                        default:
                            console.error(
                                "Unknown message type from worker:",
                                type
                            );
                    }
                } catch (error) {
                    console.error("Error handling worker message:", error);
                    this.#showErrorMessage();
                }
            };

            // Add error event listener to worker
            this.#worker.onerror = (error) => {
                console.error("Worker error:", error);
                this.#showErrorMessage();
            };
        } catch (error) {
            console.error("Error initializing worker:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {number} clientWidth
     * @param {number} clientHeight
     */
    #handleResize(clientWidth, clientHeight) {
        try {
            const sizeMultiplier = 1;

            this.width = Math.floor(clientWidth * sizeMultiplier);
            this.height = Math.floor(clientHeight * sizeMultiplier);

            this.offsetX = (this.width - clientWidth) / 2;
            this.offsetY = (this.height - clientHeight) / 2;

            // Update position with actual dimensions
            this.#cachedPosition.updateDimensions(clientWidth, clientHeight);

            this.#renderWake();

            if (this.#workerInitialized) {
                this.#updateWorkerPosition();
            }
        } catch (error) {
            console.error("Error in handleResize:", error);
            this.#showErrorMessage();
        }
    }

    async #handleWorkerInitComplete() {
        try {
            this.#updateWorkerPosition();

            this.#worker.postMessage({ type: "workCycle" });

            this.#workerInitialized = true;
        } catch (error) {
            console.error("Error in handleWorkerInitComplete:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {WheelEvent} event
     */
    #handleWheel(event) {
        try {
            event.preventDefault();

            const scrollZoomFactor = Math.pow(
                Math.pow(2, Math.pow(2, this.scrollZoomRate || 1)),
                0.1
            );

            this.#cachedPosition.updatePosition(
                event.offsetX + this.offsetX,
                event.offsetY + this.offsetY,
                event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
            );

            this.#updateWorkerPosition();

            this.#renderWake();
        } catch (error) {
            console.error("Error in handleWheel:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {CustomEvent} event
     */
    #handlePointerDrag(event) {
        try {
            event = event.detail;
            if (!this.clickZoom) {
                this.#cachedPosition.move(event.deltaX, event.deltaY);

                this.#updateWorkerPosition();

                this.#renderWake();
            }
        } catch (error) {
            console.error("Error in handlePointerDrag:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {CustomEvent} event
     */
    #handlePointerZoom(event) {
        try {
            event.preventDefault();
            event = event.detail;

            const scrollZoomFactor = event.scale;

            this.#cachedPosition.updatePosition(
                event.offsetX + this.offsetX,
                event.offsetY + this.offsetY,
                scrollZoomFactor
            );

            this.#updateWorkerPosition();

            this.#renderWake();
        } catch (error) {
            console.error("Error in handlePointerZoom:", error);
            this.#showErrorMessage();
        }
    }

    #handleMouseDown() {
        try {
            this.#isMouseDown = true;
            this.#lastMouseDownTime = performance.now();
            if (this.clickZoom) {
                this.#renderWake();
            }
        } catch (error) {
            console.error("Error in handleMouseDown:", error);
            this.#showErrorMessage();
        }
    }

    #handleMouseUp() {
        try {
            this.#isMouseDown = false;
        } catch (error) {
            console.error("Error in handleMouseUp:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {MouseEvent} event
     */
    #handleMouseMove(event) {
        try {
            this.#mouseX = event.offsetX;
            this.#mouseY = event.offsetY;
        } catch (error) {
            console.error("Error in handleMouseMove:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {TouchEvent} event
     */
    #handleTouchStart(event) {
        try {
            event.preventDefault();
            this.#isMouseDown = true;
            this.#mouseX = event.touches[0].clientX;
            this.#mouseY = event.touches[0].clientY;
            if (this.clickZoom) {
                this.#renderWake();
            }
        } catch (error) {
            console.error("Error in handleTouchStart:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {TouchEvent} event
     */
    #handleTouchEnd(event) {
        try {
            event.preventDefault();
            this.#isMouseDown = false;
        } catch (error) {
            console.error("Error in handleTouchEnd:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {TouchEvent} event
     */
    #handleTouchMove(event) {
        try {
            event.preventDefault();
            this.#mouseX = event.touches[0].clientX;
            this.#mouseY = event.touches[0].clientY;
        } catch (error) {
            console.error("Error in handleTouchMove:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {KeyboardEvent} event
     */
    #handleKeyDown(event) {
        try {
            const arrowKeys = [
                "ArrowUp",
                "ArrowDown",
                "ArrowLeft",
                "ArrowRight",
            ];
            if (arrowKeys.includes(event.key)) {
                event.preventDefault();
                if (!this.#pressedKeys[event.key]) {
                    this.#keyPressStartTimes[event.key] = performance.now();
                    this.#pressedKeys[event.key] = true;
                }
                this.#renderWake();
            }
        } catch (error) {
            console.error("Error in handleKeyDown:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {KeyboardEvent} event
     */
    #handleKeyUp(event) {
        try {
            const arrowKeys = [
                "ArrowUp",
                "ArrowDown",
                "ArrowLeft",
                "ArrowRight",
            ];
            if (arrowKeys.includes(event.key)) {
                event.preventDefault();
                this.#pressedKeys[event.key] = false;
                this.#renderWake();
            }
        } catch (error) {
            console.error("Error in handleKeyUp:", error);
            this.#showErrorMessage();
        }
    }

    #pushImage() {
        try {
            let data, offsetX, offsetY, zoom;

            let clipX, clipY, clipWidth, clipHeight;

            if (this.#pushCache) {
                data = this.#pushCache.data;
                clipX = this.#pushCache.clipX;
                clipY = this.#pushCache.clipY;
                clipWidth = this.#pushCache.clipWidth;
                clipHeight = this.#pushCache.clipHeight;

                this.#pushCache = undefined;
            }

            offsetX = this.#cachedPosition.offsetX - this.offsetX;
            offsetY = this.#cachedPosition.offsetY - this.offsetY;
            zoom = this.#cachedPosition.zoom;

            if (this.#loading) {
                if (!data) {
                    return;
                }

                this.#loading = false;
                this.#canvasFadeIn();
            }

            const startTime = performance.now();

            if (data) {
                this.#displayCanvas.width = data.width;
                this.#displayCanvas.height = data.height;
                this.#displayCtx.transferFromImageBitmap(data);

                this.#displayCanvas.style.clipPath = `xywh(${clipX}px ${clipY}px ${clipWidth}px ${clipHeight}px)`;
            }

            this.#transformCanvas(
                this.#displayCanvasParent,
                offsetX,
                offsetY,
                zoom * this.#displayCanvasBaseScale
            );

            const endTime = performance.now();
            const totalTime = endTime - startTime;
            if (totalTime > 3) {
                console.log("render time:", totalTime);
            }
        } catch (error) {
            console.error("Error in pushImage:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @param {HTMLElement} toTransform
     * @param {number} offsetX
     * @param {number} offsetY
     * @param {number} zoom
     */
    #transformCanvas(toTransform, offsetX, offsetY, zoom) {
        try {
            toTransform.style.transform = `
                matrix(
                    ${zoom},
                    0, 0,
                    ${zoom},
                    ${offsetX}, ${offsetY}
                )
            `;
        } catch (error) {
            console.error("Error in transformCanvas:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @private
     * @returns {Promise<void>}
     */
    async #canvasFadeIn() {
        try {
            const animationDuration = 1000; // 1 second
            const animationStartTime = performance.now();

            if (this.#canvasFadingIn) {
                return;
            }

            this.#canvasFadingIn = true;
            this.#canvasFadingOut = false;

            const startingOpacity = Number(
                this.#canvasLoadingAnimation.style.opacity
            );

            const animateOpacity = () => {
                try {
                    const currentTime = performance.now();
                    const elapsed = currentTime - animationStartTime;
                    const opacity = Math.max(
                        0,
                        startingOpacity - elapsed / animationDuration
                    );

                    this.#canvasLoadingAnimation.style.opacity = opacity;

                    if (opacity > 0 && this.#canvasFadingIn) {
                        requestAnimationFrame(animateOpacity);
                    } else {
                        if (opacity === 0) {
                            this.#canvasLoadingAnimation.style.display = "none";
                        }
                        this.#canvasFadingIn = false;
                    }
                } catch (error) {
                    console.error("Error in animateOpacity (fade in):", error);
                    this.#showErrorMessage();
                }
            };

            animateOpacity();
        } catch (error) {
            console.error("Error in canvasFadeIn:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @private
     * @returns {Promise<void>}
     */
    async #canvasFadeOut() {
        try {
            const animationDuration = 1000; // 1 second
            const animationStartTime = performance.now();

            if (this.#canvasFadingOut) {
                return;
            }

            this.#canvasFadingIn = false;
            this.#canvasFadingOut = true;

            const startingOpacity = Number(
                this.#canvasLoadingAnimation.style.opacity
            );

            if (startingOpacity === 0) {
                this.#canvasLoadingAnimation.style.removeProperty("display");
            }

            const animateOpacity = () => {
                try {
                    const currentTime = performance.now();
                    const elapsed = currentTime - animationStartTime;
                    const opacity = Math.min(
                        1,
                        startingOpacity + elapsed / animationDuration
                    );

                    this.#canvasLoadingAnimation.style.opacity = opacity;

                    if (opacity < 1 && this.#canvasFadingOut) {
                        requestAnimationFrame(animateOpacity);
                    } else {
                        this.#canvasFadingOut = false;
                    }
                } catch (error) {
                    console.error("Error in animateOpacity (fade out):", error);
                    this.#showErrorMessage();
                }
            };

            animateOpacity();
        } catch (error) {
            console.error("Error in canvasFadeOut:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @private
     */
    #startRenderLoop() {
        try {
            this.#renderLoop = () => {
                try {
                    if (!this.#imageDirty) {
                        return;
                    }

                    this.#imageDirty = false;

                    const currentFrameTime = performance.now();

                    if (this.#workerInitialized) {
                        if (!this.#loading) {
                            let positionChanged = false;

                            // Handle click zoom with proper timing
                            if (this.#isMouseDown && this.clickZoom) {
                                // Calculate time since mouse was pressed down
                                const mouseDeltaTime = Math.min(
                                    (currentFrameTime -
                                        this.#lastMouseDownTime) /
                                        1000,
                                    0.1 // Cap at 100ms for stability while allowing smooth movement
                                );

                                // Update last mouse down time for next frame
                                this.#lastMouseDownTime = currentFrameTime;

                                const zoomFactor = Math.pow(
                                    Math.pow(
                                        2,
                                        Math.pow(2, this.clickZoomRate || 1)
                                    ),
                                    mouseDeltaTime
                                );

                                this.#cachedPosition.updatePosition(
                                    this.#mouseX + this.offsetX,
                                    this.#mouseY + this.offsetY,
                                    zoomFactor
                                );

                                this.#imageDirty = true;

                                positionChanged = true;
                            }

                            // Handle arrow key movement with proper timing
                            if (
                                this.#pressedKeys["ArrowUp"] ||
                                this.#pressedKeys["ArrowDown"] ||
                                this.#pressedKeys["ArrowLeft"] ||
                                this.#pressedKeys["ArrowRight"]
                            ) {
                                let offsetX = 0;
                                let offsetY = 0;
                                const arrowKeys = [
                                    "ArrowUp",
                                    "ArrowDown",
                                    "ArrowLeft",
                                    "ArrowRight",
                                ];

                                for (const key of arrowKeys) {
                                    if (!this.#pressedKeys[key]) continue;

                                    // Calculate time since key was first pressed or last frame
                                    const keyDeltaTime = Math.min(
                                        (currentFrameTime -
                                            (this.#keyPressStartTimes[key] ||
                                                currentFrameTime)) /
                                            1000,
                                        0.1 // Cap at 100ms for stability while allowing smooth movement
                                    );

                                    // Update time for next frame
                                    this.#keyPressStartTimes[key] =
                                        currentFrameTime;

                                    // Adjust move speed based on canvas dimensions
                                    const moveSpeed =
                                        Math.min(this.width, this.height) *
                                        keyDeltaTime;

                                    if (key === "ArrowUp") {
                                        offsetY += moveSpeed;
                                    } else if (key === "ArrowDown") {
                                        offsetY -= moveSpeed;
                                    } else if (key === "ArrowLeft") {
                                        offsetX += moveSpeed;
                                    } else if (key === "ArrowRight") {
                                        offsetX -= moveSpeed;
                                    }
                                }

                                if (offsetX !== 0 || offsetY !== 0) {
                                    this.#cachedPosition.move(offsetX, offsetY);
                                    this.#imageDirty = true;

                                    positionChanged = true;
                                }
                            }

                            if (positionChanged) {
                                this.#updateWorkerPosition();
                            }
                        }

                        this.#pushImage();
                    }

                    if (this.#imageDirty) {
                        requestAnimationFrame(this.#renderLoop);
                    }
                } catch (error) {
                    console.error("Error in render loop:", error);
                    this.#showErrorMessage();
                }
            };

            requestAnimationFrame(this.#renderLoop);
        } catch (error) {
            console.error("Error starting render loop:", error);
            this.#showErrorMessage();
        }
    }

    #updateWorkerPosition() {
        try {
            if (this.#initializedWorkerPosition) {
                this.#worker.postMessage({
                    type: "updatePosition",
                    offsetX: this.#cachedPosition.offsetX,
                    offsetY: this.#cachedPosition.offsetY,
                    zoom: this.#cachedPosition.zoom,
                    viewportWidth: this.width || 1,
                    viewportHeight: this.height || 1,
                    version: this.#positionVersion,
                });
            } else {
                this.#canvasFadeOut();

                this.#loading = true;

                this.#initializedWorkerPosition = true;

                this.#worker.postMessage({
                    type: "resetPosition",
                    viewportWidth: this.width || 1,
                    viewportHeight: this.height || 1,
                });
            }
        } catch (error) {
            console.error("Error in updateWorkerPosition:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @private
     */
    #renderWake() {
        try {
            if (!this.#imageDirty) {
                this.#imageDirty = true;
                requestAnimationFrame(this.#renderLoop);
            }
        } catch (error) {
            console.error("Error in renderWake:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @private
     */
    #cleanupResources() {
        try {
            // Clean up pointer handler
            if (this.#pointerHandler) {
                this.#pointerHandler.destroy();
                this.#pointerHandler = null;
            }

            // Disconnect resize observer
            if (this.#resizeObserver) {
                this.#resizeObserver.disconnect();
                this.#resizeObserver = null;
            }

            // Remove event listeners
            this.removeEventListener("wheel", this.addEventListener);
            this.removeEventListener("pointerdrag", this.addEventListener);
            this.removeEventListener("pointerzoom", this.addEventListener);
            this.removeEventListener("mousedown", this.addEventListener);
            this.removeEventListener("mouseup", this.addEventListener);
            this.removeEventListener("mousemove", this.addEventListener);
            this.removeEventListener("touchstart", this.addEventListener);
            this.removeEventListener("touchend", this.addEventListener);
            this.removeEventListener("touchmove", this.addEventListener);

            document.removeEventListener("keydown", this.addEventListener);
            document.removeEventListener("keyup", this.addEventListener);

            // Close ImageBitmap if it exists
            if (this.#pushCache && this.#pushCache.data) {
                try {
                    this.#pushCache.data.close();
                } catch (e) {
                    console.error("Error closing ImageBitmap:", e);
                }
                this.#pushCache = null;
            }

            // Terminate worker
            if (this.#worker) {
                this.#worker.terminate();
                this.#worker = null;
            }
        } catch (error) {
            console.error("Error cleaning up resources:", error);
            // Don't call showErrorMessage here to avoid potential infinite loop
        }
    }

    /**
     * @private
     * @param {File} file
     * @returns {Promise<Uint8Array>}
     */
    async #readFileIntoArray(file) {
        try {
            return new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => {
                    try {
                        const arrayBuffer = reader.result;
                        const uint8Array = new Uint8Array(arrayBuffer);
                        resolve(uint8Array);
                    } catch (error) {
                        reject(error);
                    }
                };
                reader.onerror = reject;
                reader.readAsArrayBuffer(file);
            });
        } catch (error) {
            console.error("Error in readFileIntoArray:", error);
            this.#showErrorMessage();
            throw error;
        }
    }

    /**
     * @private
     * @param {File} file
     * @returns {Promise<HTMLImageElement>}
     */
    async #loadImage(file) {
        try {
            return new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => {
                    const image = new Image();
                    image.onload = () => resolve(image);
                    image.onerror = (e) => {
                        console.error("Error loading image:", e);
                        reject(e);
                    };
                    image.src = reader.result;
                };
                reader.onerror = (e) => {
                    console.error("Error reading file:", e);
                    reject(e);
                };
                reader.readAsDataURL(file);
            });
        } catch (error) {
            console.error("Error in loadImage:", error);
            this.#showErrorMessage();
            throw error;
        }
    }

    /**
     * @private
     * @param {HTMLImageElement} image
     * @param {number} maxWidth
     * @param {number} maxHeight
     * @returns {HTMLCanvasElement}
     */
    #resizeImage(image, maxWidth, maxHeight) {
        try {
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
        } catch (error) {
            console.error("Error in resizeImage:", error);
            this.#showErrorMessage();
            throw error;
        }
    }

    /**
     * @private
     * @param {HTMLCanvasElement} canvas
     * @returns {ImageData}
     */
    #getImageData(canvas) {
        try {
            const ctx = canvas.getContext("2d");
            return ctx.getImageData(0, 0, canvas.width, canvas.height);
        } catch (error) {
            console.error("Error in getImageData:", error);
            this.#showErrorMessage();
            throw error;
        }
    }

    /**
     * @public
     * @param {File} imageFile
     * @param {number} resolution
     * @returns {Promise<void>}
     */
    async searchImage(imageFile, resolution) {
        try {
            // Ensure resolution is a power of 2 or default to 1024
            if (!resolution) {
                resolution = 1024;
            } else {
                // Check if resolution is a power of 2
                const isPowerOf2 = (num) => Math.log2(num) % 1 === 0;
                if (!isPowerOf2(resolution)) {
                    console.warn(
                        "Resolution must be a power of 2. Defaulting to 1024."
                    );
                    resolution = 1024;
                }
            }

            const image = await this.#loadImage(imageFile);
            const resizedImage = this.#resizeImage(
                image,
                resolution,
                resolution
            );
            const imageData = this.#getImageData(resizedImage);

            this.#canvasFadeOut();
            this.#loading = true;

            await new Promise((resolve, reject) => {
                const handleWorkerMessage = (e) => {
                    if (e.data.type === "findImageComplete") {
                        this.#worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        resolve();
                    }
                };

                this.#worker.addEventListener("message", handleWorkerMessage);
                this.#worker.addEventListener("error", (error) => {
                    console.error("Worker error during searchImage:", error);
                    this.#worker.removeEventListener(
                        "message",
                        handleWorkerMessage
                    );
                    this.#showErrorMessage();
                    reject(error);
                });

                this.#worker.postMessage({
                    type: "findImage",
                    findImageData: imageData,
                });
            });
        } catch (error) {
            console.error("Error in searchImage:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @public
     * @param {File} file
     * @returns {Promise<void>}
     */
    async loadFile(file) {
        try {
            const fileInputContents = await this.#readFileIntoArray(file);

            if (fileInputContents && fileInputContents.length >= 1) {
                this.#canvasFadeOut();
                this.#loading = true;

                await new Promise((resolve, reject) => {
                    const handleWorkerMessage = (e) => {
                        if (e.data.type === "setOffsetComplete") {
                            this.#worker.removeEventListener(
                                "message",
                                handleWorkerMessage
                            );
                            resolve();
                        }
                    };

                    this.#worker.addEventListener(
                        "message",
                        handleWorkerMessage
                    );
                    this.#worker.addEventListener("error", (error) => {
                        console.error("Worker error during loadFile:", error);
                        this.#worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        this.#showErrorMessage();
                        reject(error);
                    });

                    this.#worker.postMessage({
                        type: "setOffset",
                        offsetArray: fileInputContents,
                    });
                });
            }
        } catch (error) {
            console.error("Error in loadFile:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @public
     * @returns {Promise<void>}
     */
    async savePosition() {
        try {
            return new Promise((resolve, reject) => {
                const handleWorkerMessage = (e) => {
                    if (e.data.type === "saveOffsetComplete") {
                        this.#worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        resolve();
                    }
                };

                this.#worker.addEventListener("message", handleWorkerMessage);
                this.#worker.addEventListener("error", (error) => {
                    console.error("Worker error during savePosition:", error);
                    this.#worker.removeEventListener(
                        "message",
                        handleWorkerMessage
                    );
                    this.#showErrorMessage();
                    reject(error);
                });

                this.#worker.postMessage({
                    type: "saveOffset",
                });
            });
        } catch (error) {
            console.error("Error in savePosition:", error);
            this.#showErrorMessage();
        }
    }

    /**
     * @public
     * @param {number} resolution
     * @returns {Promise<void>}
     */
    async saveImage(resolution) {
        try {
            if (!resolution) {
                resolution = 1024;
            } else {
                // Check if resolution is a power of 2
                const isPowerOf2 = (num) => Math.log2(num) % 1 === 0;
                if (!isPowerOf2(resolution)) {
                    console.warn(
                        "Resolution must be a power of 2. Defaulting to 1024."
                    );
                    resolution = 1024;
                }
            }

            return new Promise((resolve, reject) => {
                const handleWorkerMessage = (e) => {
                    if (e.data.type === "makeImageComplete") {
                        this.#worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        resolve();
                    }
                };

                this.#worker.addEventListener("message", handleWorkerMessage);
                this.#worker.addEventListener("error", (error) => {
                    console.error("Worker error during saveImage:", error);
                    this.#worker.removeEventListener(
                        "message",
                        handleWorkerMessage
                    );
                    this.#showErrorMessage();
                    reject(error);
                });

                this.#worker.postMessage({
                    type: "makeImage",
                    imageSquareSize: resolution,
                });
            });
        } catch (error) {
            console.error("Error in saveImage:", error);
            this.#showErrorMessage();
        }
    }
}

customElements.define("canvas-component", CanvasComponent);
