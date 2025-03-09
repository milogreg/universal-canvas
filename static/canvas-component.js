"use strict";

/**
 * @typedef {Object} Point
 * @property {number} x - The x coordinate
 * @property {number} y - The y coordinate
 */

/**
 * @typedef {Object} OffsetInfo
 * @property {number} offsetX - The x offset
 * @property {number} offsetY - The y offset
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
     * Adds a new pointer to the manager
     * @param {number} id - Pointer identifier
     * @param {number} x - X coordinate
     * @param {number} y - Y coordinate
     */
    addPointer(id, x, y) {
        this.pointers.set(id, { x, y });
        this.updateReferenceCentroid();
    }

    /**
     * Updates an existing pointer's position
     * @param {number} id - Pointer identifier
     * @param {number} x - New X coordinate
     * @param {number} y - New Y coordinate
     */
    updatePointer(id, x, y) {
        if (this.pointers.has(id)) {
            this.pointers.set(id, { x, y });
        }
    }

    /**
     * Removes a pointer from the manager
     * @param {number} id - Pointer identifier to remove
     */
    removePointer(id) {
        this.pointers.delete(id);
        this.updateReferenceCentroid();
    }

    /**
     * Gets the current number of active pointers
     * @returns {number} The count of active pointers
     */
    getPointerCount() {
        return this.pointers.size;
    }

    /**
     * Calculates the centroid (average position) of all active pointers
     * @returns {Point|null} The centroid point or null if no pointers
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
     * Calculates the average distance of all pointers from a centroid
     * @param {Point|null} centroid - The centroid point
     * @returns {number} The average distance from the centroid
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
     * Gets the offset between the reference centroid and a new centroid
     * @param {Point|null} newCentroid - The new centroid to compare against
     * @returns {OffsetInfo} The x and y offsets
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
     * Calculates the scale factor based on pointer movement from the reference centroid
     * @param {Point|null} newCentroid - The new centroid
     * @returns {number} The scale factor
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
 * @typedef {Object} VelocityEntry
 * @property {number} time - Timestamp of the entry
 * @property {number} velX - X velocity
 * @property {number} velY - Y velocity
 * @property {number} velScale - Scale velocity
 */

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
     * Creates a new PointerHandler
     * @param {HTMLElement} element - The DOM element to attach the handler to
     * @param {number} [friction=0.99] - Friction coefficient for momentum calculations
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
     * Handles pointer down events
     * @param {PointerEvent} event - The pointer down event
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
     * Handles pointer move events
     * @param {PointerEvent} event - The pointer move event
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
     * Handles pointer up events
     * @param {PointerEvent} event - The pointer up event
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
     * Cleans up old entries from the velocity history
     * @param {number} currentTime - The current timestamp
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
         * Applies friction to a velocity value
         * @param {number} v - The velocity value
         * @returns {number} The velocity after applying friction
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
     * Creates a new ClientPosition
     * @param {number} zoom - Initial zoom level
     * @param {number} offsetX - Initial X offset
     * @param {number} offsetY - Initial Y offset
     * @param {number} canvasWidth - Canvas width
     * @param {number} canvasHeight - Canvas height
     */
    constructor(zoom, offsetX, offsetY, canvasWidth, canvasHeight) {
        this.zoom = zoom;
        this.offsetX = offsetX;
        this.offsetY = offsetY;
        this.canvasWidth = canvasWidth;
        this.canvasHeight = canvasHeight;
    }

    /**
     * Updates position based on mouse position and zoom delta
     * @param {number} mouseX - Mouse X position
     * @param {number} mouseY - Mouse Y position
     * @param {number} zoomDelta - Zoom change factor
     */
    updatePosition(mouseX, mouseY, zoomDelta) {
        this.zoom *= zoomDelta;
        this.offsetX = mouseX - (mouseX - this.offsetX) * zoomDelta;
        this.offsetY = mouseY - (mouseY - this.offsetY) * zoomDelta;
    }

    /**
     * Moves the position by the specified offset
     * @param {number} offsetX - X offset to move by
     * @param {number} offsetY - Y offset to move by
     */
    move(offsetX, offsetY) {
        this.offsetX += offsetX;
        this.offsetY += offsetY;
    }

    /**
     * Updates canvas dimensions while maintaining relative position
     * @param {number} canvasWidth - New canvas width
     * @param {number} canvasHeight - New canvas height
     */
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

/**
 * @typedef {Object} PushCacheData
 * @property {ImageBitmap|null} data - Main image bitmap
 * @property {ImageBitmap|null} oldData - Old image bitmap
 */

/**
 * A custom web component that displays a canvas with pan and zoom capabilities
 * @extends HTMLElement
 */
class CanvasComponent extends HTMLElement {
    // Public properties
    /** @type {number} Zoom rate for click-based zooming */
    clickZoomRate = 1;

    /** @type {number} Zoom rate for scroll-based zooming */
    scrollZoomRate = 1;

    /** @type {boolean} Whether click-to-zoom is enabled */
    clickZoom = false;

    // Private fields
    /** @type {Worker|null} Web worker for processing */
    #worker = null;

    /** @type {PointerHandler|null} Handler for pointer events */
    #pointerHandler = null;

    /** @type {ResizeObserver|null} Observer for size changes */
    #resizeObserver = null;

    /** @type {ClientPosition|null} Current position information */
    #cachedPosition = null;

    /** @type {ClientPosition|null} Previous position information */
    #oldCachedPosition = null;

    /** @type {PushCacheData|null} Cache for image data */
    #pushCache = null;

    /** @type {boolean} Whether the component is loading */
    #loading = true;

    /** @type {boolean} Whether the image needs to be redrawn */
    #imageDirty = true;

    /** @type {boolean} Whether the worker has been initialized */
    #workerInitialized = false;

    /** @type {boolean} Whether canvas fade-in animation is active */
    #canvasFadingIn = false;

    /** @type {boolean} Whether canvas fade-out animation is active */
    #canvasFadingOut = false;

    /** @type {Object.<string, boolean>} Map of currently pressed keys */
    #pressedKeys = {};

    /** @type {HTMLCanvasElement|null} Main display canvas */
    #displayCanvas = null;

    /** @type {ImageBitmapRenderingContext|null} Context for main canvas */
    #displayCtx = null;

    /** @type {HTMLCanvasElement|null} Secondary display canvas */
    #oldDisplayCanvas = null;

    /** @type {ImageBitmapRenderingContext|null} Context for secondary canvas */
    #oldDisplayCtx = null;

    /** @type {HTMLDivElement|null} Loading animation element */
    #canvasLoadingAnimation = null;

    /** @type {Function|null} Render loop callback */
    #renderLoop = null;

    /** @type {boolean} Whether mouse is currently pressed */
    #isMouseDown = false;

    /** @type {number} Current mouse X position */
    #mouseX = 0;

    /** @type {number} Current mouse Y position */
    #mouseY = 0;

    /** @type {number} Timestamp of last mouse down event */
    #lastMouseDownTime = 0;

    /** @type {Object.<string, number>} Map of key press start times */
    #keyPressStartTimes = {};

    /**
     * Creates a new CanvasComponent instance
     */
    constructor() {
        super();

        // Create shadow DOM
        this.attachShadow({ mode: "open" });

        // Initialize positions
        this.#cachedPosition = new ClientPosition(1, 0, 0, 1, 1);
        this.#oldCachedPosition = new ClientPosition(1, 0, 0, 1, 1);
    }

    /**
     * Lifecycle callback when element is added to the DOM
     */
    connectedCallback() {
        // Initialize the component
        this.#initializeComponent();
        this.#setupEventListeners();
        this.#initializeWorker();
        this.#startRenderLoop();
    }

    /**
     * Lifecycle callback when element is removed from the DOM
     */
    disconnectedCallback() {
        // Clean up resources
        this.#cleanupResources();
    }

    /**
     * List of attributes that should trigger attributeChangedCallback
     * @returns {string[]} Array of attribute names to observe
     */
    static get observedAttributes() {
        return ["click-zoom-rate", "scroll-zoom-rate", "click-zoom"];
    }

    /**
     * Lifecycle callback when an observed attribute changes
     * @param {string} name - Name of the attribute
     * @param {string} oldValue - Previous attribute value
     * @param {string} newValue - New attribute value
     */
    attributeChangedCallback(name, oldValue, newValue) {
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
    }

    // Initialize component HTML and CSS
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

            #display-canvas, #old-display-canvas {
                will-change: transform;
                top: 0;
                left: 0;
                position: absolute;
                pointer-events: none;
            }

            #display-canvas {
                z-index: 0;
            }

            #old-display-canvas {
                z-index: 1;
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
        <canvas id="display-canvas"></canvas>
        <canvas id="old-display-canvas"></canvas>
        <div id="canvas-loading"></div>
        `;

        // Get DOM references
        this.#displayCanvas = this.shadowRoot.getElementById("display-canvas");
        this.#displayCanvas.width = 2048;
        this.#displayCanvas.height = 2048;
        this.#displayCtx = this.#displayCanvas.getContext("bitmaprenderer");

        this.#oldDisplayCanvas =
            this.shadowRoot.getElementById("old-display-canvas");
        this.#oldDisplayCanvas.width = 2048;
        this.#oldDisplayCanvas.height = 2048;
        this.#oldDisplayCtx =
            this.#oldDisplayCanvas.getContext("bitmaprenderer");

        this.#canvasLoadingAnimation =
            this.shadowRoot.getElementById("canvas-loading");
        this.#canvasLoadingAnimation.style.opacity = 1;

        // Initialize pointer handler
        this.#pointerHandler = new PointerHandler(this);
    }

    // Set up event listeners
    #setupEventListeners() {
        // Set up ResizeObserver
        this.#resizeObserver = new ResizeObserver((entries) => {
            for (const entry of entries) {
                const { clientWidth, clientHeight } = entry.target;
                this.#handleResize(clientWidth, clientHeight);
            }
        });

        // Observe the component
        this.#resizeObserver.observe(this);

        // Wheel event for zooming
        this.addEventListener("wheel", this.#handleWheel.bind(this));

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
        this.addEventListener("mousedown", this.#handleMouseDown.bind(this));
        this.addEventListener("mouseup", this.#handleMouseUp.bind(this));
        this.addEventListener("mousemove", this.#handleMouseMove.bind(this));

        // Touch events
        this.addEventListener("touchstart", this.#handleTouchStart.bind(this));
        this.addEventListener("touchend", this.#handleTouchEnd.bind(this));
        this.addEventListener("touchmove", this.#handleTouchMove.bind(this));

        // Keyboard events
        document.addEventListener("keydown", this.#handleKeyDown.bind(this));
        document.addEventListener("keyup", this.#handleKeyUp.bind(this));
    }

    // Initialize Web Worker
    #initializeWorker() {
        this.#worker = new Worker("wasm-worker.js");

        this.#worker.onmessage = async (e) => {
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
                        this.#pushCache.data = data;

                        this.#cachedPosition = new ClientPosition(
                            zoom,
                            offsetX,
                            offsetY,
                            this.squareSize,
                            this.squareSize
                        );
                    }

                    if (oldData) {
                        if (this.#pushCache.oldData) {
                            this.#pushCache.oldData.close();
                        }
                        this.#pushCache.oldData = oldData;

                        this.#oldCachedPosition = new ClientPosition(
                            oldZoom,
                            oldOffsetX,
                            oldOffsetY,
                            this.squareSize,
                            this.squareSize
                        );
                    }

                    this.#renderWake();
                    break;
                }
                case "zoomViewportComplete":
                case "moveViewportComplete":
                case "resizeViewportComplete":
                case "findImageComplete":
                    break;
                default:
                    console.error("Unknown message type from worker:", type);
            }
        };

        this.#worker.postMessage({ type: "workCycle" });
    }

    // Handle resize events
    #handleResize(clientWidth, clientHeight) {
        const canvasSquareSize = Math.max(clientWidth, clientHeight);

        this.width = clientWidth;
        this.height = clientHeight;

        if (clientWidth > clientHeight) {
            this.offsetX = 0;
            this.offsetY = (clientWidth - clientHeight) / 2;
        } else {
            this.offsetX = (clientHeight - clientWidth) / 2;
            this.offsetY = 0;
        }

        this.squareSize = canvasSquareSize;

        this.#cachedPosition.updateDimensions(
            canvasSquareSize,
            canvasSquareSize
        );
        this.#oldCachedPosition.updateDimensions(
            canvasSquareSize,
            canvasSquareSize
        );

        this.#renderWake();

        if (this.#workerInitialized) {
            this.#worker.postMessage({
                type: "resizeViewport",
                canvasWidth: canvasSquareSize,
                canvasHeight: canvasSquareSize,
            });
        }
    }

    // Handle worker messages
    async #handleWorkerMessage(e) {
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
                this.#renderImage(
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
            case "zoomViewportComplete":
            case "moveViewportComplete":
            case "resizeViewportComplete":
            case "findImageComplete":
                break;
            default:
                console.error("Unknown message type from worker:", type);
        }
    }

    // Handle worker initialization complete
    async #handleWorkerInitComplete() {
        await new Promise((resolve) => {
            const handleWorkerMessage = (e) => {
                if (e.data.type === "resizeViewportComplete") {
                    this.#worker.removeEventListener(
                        "message",
                        handleWorkerMessage
                    );
                    resolve();
                }
            };
            this.#worker.addEventListener("message", handleWorkerMessage);
            this.#worker.postMessage({
                type: "resizeViewport",
                canvasWidth: this.squareSize,
                canvasHeight: this.squareSize,
            });
        });

        await new Promise((resolve) => {
            const handleWorkerMessage = (e) => {
                if (e.data.type === "zoomViewportComplete") {
                    this.#worker.removeEventListener(
                        "message",
                        handleWorkerMessage
                    );
                    resolve();
                }
            };

            const mouseX = this.width / 2;
            const mouseY = this.height / 2;
            const zoomFactor =
                (Math.min(this.width, this.height) / this.squareSize) * 0.8;

            this.#worker.addEventListener("message", handleWorkerMessage);
            this.#worker.postMessage({
                type: "zoomViewport",
                mouseX: mouseX + this.offsetX,
                mouseY: mouseY + this.offsetY,
                zoomDelta: zoomFactor,
            });

            this.#cachedPosition.updatePosition(
                mouseX + this.offsetX,
                mouseY + this.offsetY,
                zoomFactor
            );
            this.#oldCachedPosition.updatePosition(
                mouseX + this.offsetX,
                mouseY + this.offsetY,
                zoomFactor
            );
        });

        this.#workerInitialized = true;
    }

    // Event handlers
    #handleWheel(event) {
        event.preventDefault();

        const scrollZoomFactor = Math.pow(
            Math.pow(2, Math.pow(2, this.scrollZoomRate || 1)),
            0.1
        );

        this.#worker.postMessage({
            type: "zoomViewport",
            mouseX: event.offsetX + this.offsetX,
            mouseY: event.offsetY + this.offsetY,
            zoomDelta:
                event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor,
        });

        this.#cachedPosition.updatePosition(
            event.offsetX + this.offsetX,
            event.offsetY + this.offsetY,
            event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
        );

        this.#oldCachedPosition.updatePosition(
            event.offsetX + this.offsetX,
            event.offsetY + this.offsetY,
            event.deltaY > 0 ? 1 / scrollZoomFactor : scrollZoomFactor
        );

        this.#renderWake();
    }

    #handlePointerDrag(event) {
        event = event.detail;
        if (!this.clickZoom) {
            this.#worker.postMessage({
                type: "moveViewport",
                offsetX: event.deltaX,
                offsetY: event.deltaY,
            });
            this.#cachedPosition.move(event.deltaX, event.deltaY);
            this.#oldCachedPosition.move(event.deltaX, event.deltaY);

            this.#renderWake();
        }
    }

    #handlePointerZoom(event) {
        event.preventDefault();
        event = event.detail;

        const scrollZoomFactor = event.scale;

        this.#worker.postMessage({
            type: "zoomViewport",
            mouseX: event.offsetX + this.offsetX,
            mouseY: event.offsetY + this.offsetY,
            zoomDelta: scrollZoomFactor,
        });

        this.#cachedPosition.updatePosition(
            event.offsetX + this.offsetX,
            event.offsetY + this.offsetY,
            scrollZoomFactor
        );

        this.#oldCachedPosition.updatePosition(
            event.offsetX + this.offsetX,
            event.offsetY + this.offsetY,
            scrollZoomFactor
        );

        this.#renderWake();
    }

    #handleMouseDown() {
        this.#isMouseDown = true;
        this.#lastMouseDownTime = performance.now();
        if (this.clickZoom) {
            this.#renderWake();
        }
    }

    #handleMouseUp() {
        this.#isMouseDown = false;
    }

    #handleMouseMove(event) {
        this.#mouseX = event.offsetX;
        this.#mouseY = event.offsetY;
    }

    #handleTouchStart(event) {
        event.preventDefault();
        this.#isMouseDown = true;
        this.#mouseX = event.touches[0].clientX;
        this.#mouseY = event.touches[0].clientY;
        if (this.clickZoom) {
            this.#renderWake();
        }
    }

    #handleTouchEnd(event) {
        event.preventDefault();
        this.#isMouseDown = false;
    }

    #handleTouchMove(event) {
        event.preventDefault();
        this.#mouseX = event.touches[0].clientX;
        this.#mouseY = event.touches[0].clientY;
    }

    #handleKeyDown(event) {
        const arrowKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
        if (arrowKeys.includes(event.key)) {
            event.preventDefault();
            if (!this.#pressedKeys[event.key]) {
                this.#keyPressStartTimes[event.key] = performance.now();
                this.#pressedKeys[event.key] = true;
            }
            this.#renderWake();
        }
    }

    #handleKeyUp(event) {
        const arrowKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight"];
        if (arrowKeys.includes(event.key)) {
            event.preventDefault();
            this.#pressedKeys[event.key] = false;
            this.#renderWake();
        }
    }

    // Rendering methods
    #renderImage(
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
        if (!this.#pushCache) {
            this.#pushCache = {};
        }

        if (data) {
            if (this.#pushCache.data) {
                this.#pushCache.data.close();
            }
            this.#pushCache.data = data;

            this.#cachedPosition = new ClientPosition(
                zoom,
                offsetX,
                offsetY,
                this.squareSize,
                this.squareSize
            );
        }

        if (oldData) {
            if (this.#pushCache.oldData) {
                this.#pushCache.oldData.close();
            }
            this.#pushCache.oldData = oldData;

            this.#oldCachedPosition = new ClientPosition(
                oldZoom,
                oldOffsetX,
                oldOffsetY,
                this.squareSize,
                this.squareSize
            );
        }

        this.#renderWake();
    }

    #pushImage() {
        let data,
            offsetX,
            offsetY,
            zoom,
            oldData,
            oldOffsetX,
            oldOffsetY,
            oldZoom;

        if (this.#pushCache) {
            data = this.#pushCache.data;
            oldData = this.#pushCache.oldData;
            this.#pushCache = undefined;
        }

        offsetX = this.#cachedPosition.offsetX - this.offsetX;
        offsetY = this.#cachedPosition.offsetY - this.offsetY;
        zoom = this.#cachedPosition.zoom;

        oldOffsetX = this.#oldCachedPosition.offsetX - this.offsetX;
        oldOffsetY = this.#oldCachedPosition.offsetY - this.offsetY;
        oldZoom = this.#oldCachedPosition.zoom;

        if (this.#loading) {
            if (!data) {
                return;
            }

            this.#loading = false;
            this.#canvasFadeIn();
        }

        const startTime = performance.now();

        if (data) {
            this.#displayCtx.transferFromImageBitmap(data);
            this.#oldDisplayCtx.transferFromImageBitmap(oldData);
        }

        this.#transformCanvas(this.#displayCanvas, offsetX, offsetY, zoom);
        this.#transformCanvas(
            this.#oldDisplayCanvas,
            oldOffsetX,
            oldOffsetY,
            oldZoom
        );

        const endTime = performance.now();
        const totalTime = endTime - startTime;
        if (totalTime > 3) {
            console.log("render time:", totalTime);
        }
    }

    #transformCanvas(toTransform, offsetX, offsetY, zoom) {
        const squareRatio = this.squareSize / toTransform.width;
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

    /**
     * Start the fade-in animation for the canvas
     * @private
     * @returns {Promise<void>}
     */
    async #canvasFadeIn() {
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
        };

        animateOpacity();
    }

    /**
     * Start the fade-out animation for the canvas
     * @private
     * @returns {Promise<void>}
     */
    async #canvasFadeOut() {
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
        };

        animateOpacity();
    }

    /**
     * Start the render loop
     * @private
     */
    #startRenderLoop() {
        this.#renderLoop = () => {
            if (!this.#imageDirty) {
                return;
            }

            this.#imageDirty = false;

            const currentFrameTime = performance.now();

            if (this.#workerInitialized) {
                if (!this.#loading) {
                    // Handle click zoom with proper timing
                    if (this.#isMouseDown && this.clickZoom) {
                        // Calculate time since mouse was pressed down
                        const mouseDeltaTime = Math.min(
                            (currentFrameTime - this.#lastMouseDownTime) / 1000,
                            0.1 // Cap at 100ms for stability while allowing smooth movement
                        );

                        // Update last mouse down time for next frame
                        this.#lastMouseDownTime = currentFrameTime;

                        const zoomFactor = Math.pow(
                            Math.pow(2, Math.pow(2, this.clickZoomRate || 1)),
                            mouseDeltaTime
                        );

                        this.#worker.postMessage({
                            type: "zoomViewport",
                            mouseX: this.#mouseX + this.offsetX,
                            mouseY: this.#mouseY + this.offsetY,
                            zoomDelta: zoomFactor,
                        });
                        this.#cachedPosition.updatePosition(
                            this.#mouseX + this.offsetX,
                            this.#mouseY + this.offsetY,
                            zoomFactor
                        );
                        this.#oldCachedPosition.updatePosition(
                            this.#mouseX + this.offsetX,
                            this.#mouseY + this.offsetY,
                            zoomFactor
                        );
                        this.#imageDirty = true;
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
                            this.#keyPressStartTimes[key] = currentFrameTime;

                            const moveSpeed = this.squareSize * keyDeltaTime;

                            if (key === "ArrowUp") {
                                offsetY -= moveSpeed;
                            } else if (key === "ArrowDown") {
                                offsetY += moveSpeed;
                            } else if (key === "ArrowLeft") {
                                offsetX -= moveSpeed;
                            } else if (key === "ArrowRight") {
                                offsetX += moveSpeed;
                            }
                        }

                        if (offsetX !== 0 || offsetY !== 0) {
                            this.#worker.postMessage({
                                type: "moveViewport",
                                offsetX,
                                offsetY,
                            });
                            this.#cachedPosition.move(offsetX, offsetY);
                            this.#oldCachedPosition.move(offsetX, offsetY);
                            this.#imageDirty = true;
                        }
                    }
                }

                this.#pushImage();
            }

            if (this.#imageDirty) {
                requestAnimationFrame(this.#renderLoop);
            }
        };

        requestAnimationFrame(this.#renderLoop);
    }

    /**
     * Wake up the render loop when image needs to be redrawn
     * @private
     */
    #renderWake() {
        if (!this.#imageDirty) {
            this.#imageDirty = true;
            requestAnimationFrame(this.#renderLoop);
        }
    }

    /**
     * Clean up resources when component is removed from DOM
     * @private
     */
    #cleanupResources() {
        // Clean up pointer handler
        if (this.#pointerHandler) {
            this.#pointerHandler.destroy();
        }

        // Disconnect resize observer
        if (this.#resizeObserver) {
            this.#resizeObserver.disconnect();
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

        // Terminate worker
        if (this.#worker) {
            this.#worker.terminate();
            this.#worker = null;
        }
    }

    /**
     * Read a file into an Uint8Array
     * @private
     * @param {File} file - The file to read
     * @returns {Promise<Uint8Array>} The file contents as an array
     */
    async #readFileIntoArray(file) {
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

    /**
     * Load an image from a file
     * @private
     * @param {File} file - The image file
     * @returns {Promise<HTMLImageElement>} The loaded image
     */
    async #loadImage(file) {
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

    /**
     * Resize an image to fit within maxWidth and maxHeight
     * @private
     * @param {HTMLImageElement} image - The image to resize
     * @param {number} maxWidth - Maximum width
     * @param {number} maxHeight - Maximum height
     * @returns {HTMLCanvasElement} Canvas containing the resized image
     */
    #resizeImage(image, maxWidth, maxHeight) {
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

    /**
     * Get image data from a canvas
     * @private
     * @param {HTMLCanvasElement} canvas - The canvas containing the image
     * @returns {ImageData} The image data
     */
    #getImageData(canvas) {
        const ctx = canvas.getContext("2d");
        return ctx.getImageData(0, 0, canvas.width, canvas.height);
    }

    /**
     * Searches the canvas for a provided image
     * @public
     * @param {File} imageFile - The image file to search for
     * @param {number} resolution - The resolution to search at
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

            await new Promise((resolve) => {
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
                this.#worker.postMessage({
                    type: "findImage",
                    findImageData: imageData,
                });
            });
        } catch (error) {
            console.error("Error processing file:", error);
        }
    }

    /**
     * Loads a position file into the canvas
     * @public
     * @param {File} file - The position file to load
     * @returns {Promise<void>}
     */
    async loadFile(file) {
        const fileInputContents = await this.#readFileIntoArray(file);

        if (fileInputContents && fileInputContents.length >= 1) {
            this.#canvasFadeOut();
            this.#loading = true;

            await new Promise((resolve) => {
                const handleWorkerMessage = (e) => {
                    if (e.data.type === "setOffsetComplete") {
                        this.#worker.removeEventListener(
                            "message",
                            handleWorkerMessage
                        );
                        resolve();
                    }
                };
                this.#worker.addEventListener("message", handleWorkerMessage);
                this.#worker.postMessage({
                    type: "setOffset",
                    offsetArray: fileInputContents,
                });
            });
        }
    }

    /**
     * Saves the current position to a file
     * @public
     * @returns {Promise<void>}
     */
    async savePosition() {
        return new Promise((resolve) => {
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
            this.#worker.postMessage({
                type: "saveOffset",
            });
        });
    }
}

customElements.define("canvas-component", CanvasComponent);
