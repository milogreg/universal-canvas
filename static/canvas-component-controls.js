"use strict";

class CanvasComponentControls extends HTMLElement {
    constructor() {
        super();

        /** @type {Array} */
        this.canvasComponents = [];

        /** @type {boolean} */
        this._listenersAttached = false;

        /** @type {boolean} */
        this.isDragging = false;

        // Create shadow DOM
        const shadow = this.attachShadow({ mode: "open" });

        // Add basic styles and HTML structure
        shadow.innerHTML = /*html*/ `
            <style>
                :host {
                    --bg-button: #3b82a3;
                    --bg-button-hover: #2b6783;
                    --bg-primary: #eeeeee;
                    --bg-secondary: #f5f5f5;
                    --border-color: #a0a0a0;
                    --text-primary: #222222;
                    --color-button: #f5f5f5;
                    --shadow: 0 0.125rem 0.25rem rgba(0, 0, 0, 0.25);
                    --border-radius: 0.25rem;
                    --transition: all 0.1s ease;    
                   
                    color: var(--text-primary);
                   
                    container-type: inline-size; /* For container queries */
                }
                
                /* Dark mode */
                @media (prefers-color-scheme: dark) {
                    :host {
                        --bg-button: #2b6783;
                        --bg-button-hover: #204d63;
                        --bg-primary: #222222;
                        --bg-secondary: #2e2e2e;
                        --border-color: #898989;
                        --text-primary: #e7e7e7;
                        --shadow: 0 0.125rem 0.25rem rgba(0, 0, 0, 0.4);
                    }
                }
                
                /* Layout */
                .component-container {
                    overflow: hidden;
                    width: 100%;
                    height: 100%;
                    position: relative;
                }
                
                .layout-container {
                    width: 100%;
                    height: 100%;
                    display: flex;
                }

                div {
                    box-sizing: border-box;
                }
                
                .controls-container {
                    background-color: var(--bg-primary);
                    height: 100%;
                    display: flex;
                    flex-direction: column;
                    gap: 0.5rem;
                    max-width: 100%;
                    overflow-y: auto;
                    padding: 0 0.5rem;
                    transition: var(--transition);
                    z-index: 10;
                }
                
                .canvas-container {
                    display: flex;
                    flex: 1;
                    flex-direction: column;
                    position: relative;
                    z-index: 1;
                }
                
                /* Menu toggle */
                #menu-toggle, #fullscreen-toggle {
                    opacity: 0;
                    position: absolute;
                    height: 0;
                    width: 0;
                }
                
                .menu-toggle-label {
                    background-color: var(--bg-button);
                    border-radius: var(--border-radius);
                    box-shadow: var(--shadow);
                    color: var(--color-button);
                    cursor: pointer;
                    padding: 0.35rem 0.5rem;
                    position: absolute;
                    left: 1rem;
                    top: 1rem;
                    transition: var(--transition);
                    display: none;
                    align-items: center;
                    gap: 0.25rem;
                    z-index: 200;
                    font-weight: 500;
                }
                
                .menu-toggle-label:hover {
                    background-color: var(--bg-button-hover);
                }
                
                /* Add focus styles that match hover styles */
                .menu-toggle-label:focus-visible,
                .fullscreen-toggle-label:focus-visible,
                button:focus-visible {
                    background-color: var(--bg-button-hover);
                    outline: 2px solid var(--text-primary);
                    outline-offset: 2px;
                }
                
                .menu-arrow {
                    display: inline-block;
                    width: 1.25rem;
                    height: 0.75rem;
                    color: var(--color-button);
                    transition: transform 0.2s ease;
                }
                
                #menu-toggle:checked ~ .component-container .menu-arrow {
                    transform: rotate(180deg);
                }
                
                .fullscreen-toggle-label {
                    background-color: var(--bg-button);
                    border-radius: var(--border-radius);
                    box-shadow: var(--shadow);
                    color: var(--color-button);
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    height: 2rem;
                    width: 2rem;
                    padding: 0.3rem;
                    position: absolute;
                    right: 1rem;
                    bottom: 1rem;
                    transition: var(--transition);
                    z-index: 100;
                }

                .fullscreen-toggle-label svg {
                    height: 100%;
                    width: 100%;
                    fill: var(--color-button);
                }
                
                .fullscreen-toggle-label:hover {
                    background-color: var(--bg-button-hover);
                }
                
                #fullscreen-toggle:checked ~ .component-container .expand-icon,
                #fullscreen-toggle:not(:checked) ~ .component-container .collapse-icon {
                    display: none;
                }
                
                /* Responsive layout */
                @container (max-width: 60rem) {
                    .component-container .menu-toggle-label {
                        display: flex;
                    }
                    
                    .controls-container {
                        border-right: 1px solid var(--border-color);
                        box-shadow: 0.125rem 0 0.3125rem rgba(0, 0, 0, 0.1);
                        position: absolute;
                        transform: translateX(-110%);
                        z-index: 150;
                        padding-top: 3.9rem;
                    }
                }
                
                /* Show menu in fullscreen mode */
                #fullscreen-toggle:checked ~ .component-container .menu-toggle-label {
                    display: flex;
                }
                
                /* Menu position in fullscreen mode */
                #fullscreen-toggle:checked ~ .component-container .controls-container {
                    border-right: 0.0625rem solid var(--border-color);
                    box-shadow: 0.125rem 0 0.3125rem rgba(0, 0, 0, 0.1);
                    position: absolute;
                    transform: translateX(-110%);
                    z-index: 150;
                    padding-top: 3.9rem;
                }
                
                /* Show menu when checked */
                #menu-toggle:checked ~ .component-container .layout-container .controls-container {
                    transform: translateX(0);
                }
                
                /* Control elements */
                .control-group {
                    border: 1px solid  var(--border-color);
                    background-color: var(--bg-secondary);
                    padding: 0.5rem;
                }
                
                .control-group-label {
                    font-size: 1.2rem;
                    font-weight: bold;
                }

                .spacer-1 {
                    height: 0.5rem;
                }
 
                /* Form elements */
                input[type="range"], select {
                    width: 100%;
                }
                
                .file-upload-label {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    border: 2px dashed var(--border-color);
                    border-radius: var(--border-radius);
                    background: var(--bg-primary);
                    cursor: pointer;
                    padding: 0.25rem;
                    text-align: center;
                }
                
                .file-upload-container input[type="file"] {
                    display: none;
                }
                
                /* Buttons */
                button {
                    background-color: var(--bg-button);
                    border: none;
                    border-radius: var(--border-radius);
                    color: white;
                    cursor: pointer;
                    padding: 0.5rem 1rem;
                }
                
                button:hover {
                    background-color: var(--bg-button-hover);
                }
                
                /* Slot for canvas components */
                ::slotted(canvas-component) {
                    flex-grow: 1;
                    width: 100%;
                }
                
                /* Drag and drop overlay */
                .drag-drop-overlay {
                    display: none;
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    background-color: rgba(59, 130, 163, 0.7);
                    z-index: 300;
                    justify-content: center;
                    align-items: center;
                    pointer-events: none;
                }
                
                .drag-drop-overlay.active {
                    display: flex;
                }
                
                .drag-drop-content {
                    background-color: var(--bg-primary);
                    border: 3px dashed var(--border-color);
                    border-radius: var(--border-radius);
                    padding: 2rem;
                    text-align: center;
                    max-width: 80%;
                    pointer-events: none;
                }
                
                .drag-drop-content svg {
                    width: 4rem;
                    height: 4rem;
                    margin-bottom: 1rem;
                    fill: var(--bg-button);
                }
                
                .drag-drop-title {
                    font-size: 1.5rem;
                    margin-bottom: 0.5rem;
                    color: var(--text-primary);
                }
                
                .drag-drop-desc {
                    color: var(--text-primary);
                }
            </style>
            
            <!-- Menu toggle checkbox -->
            <input type="checkbox" id="menu-toggle" aria-label="Toggle menu visibility">
            
            <!-- Fullscreen toggle checkbox -->
            <input type="checkbox" id="fullscreen-toggle" aria-label="Toggle fullscreen view">
            
            <div class="component-container" role="application" aria-label="Canvas Component Controls">
                <!-- Menu toggle button -->
                <label for="menu-toggle" class="menu-toggle-label" aria-label="Toggle menu" tabindex="0">
                    <span>Menu</span>
                    <svg class="menu-arrow" viewBox="0 0 24 12" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                        <path d="M3 6H18M13 1L18 6L13 11" stroke="currentColor" stroke-width="2" stroke-linecap="butt" stroke-linejoin="miter" fill="none"/>
                    </svg>
                </label>
                
                <div class="layout-container">
                    <div class="controls-container" role="region" aria-label="Control panel">
                        <!-- Image search -->
                        <div class="control-group" role="group" aria-labelledby="image-search-label">
                            <div class="control-group-label" id="image-search-label">Image Search</div>
                            <div class="spacer-1"></div>
                            <div class="file-upload-container">
                                <input type="file" id="find-image-input" accept="image/*" aria-label="Select an image to search">
                                <label for="find-image-input" id="file-upload-label" class="file-upload-label" tabindex="0">
                                    Select an image to search
                                </label>
                            </div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="image-resolution">Resolution:</label>
                                <select id="image-resolution" aria-label="Select image resolution">
                                    <option value="64">64px</option>
                                    <option value="128">128px</option>
                                    <option value="256">256px</option>
                                    <option value="512">512px</option>
                                    <option value="1024" selected>1024px</option>
                                    <option value="2048">2048px</option>
                                </select>
                            </div>
                        </div>

                        <!-- Save image -->
                        <div class="control-group" role="group" aria-labelledby="save-image-label">
                            <div class="control-group-label" id="save-image-label">Save Image</div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="save-image-resolution">Resolution:</label>
                                <select id="save-image-resolution" aria-label="Select save image resolution">
                                    <option value="64">64px</option>
                                    <option value="128">128px</option>
                                    <option value="256">256px</option>
                                    <option value="512">512px</option>
                                    <option value="1024" selected>1024px</option>
                                    <option value="2048">2048px</option>
                                </select>
                            </div>
                            <div class="spacer-1"></div>
                            <button id="save-image-button" aria-label="Save image">Save Image</button>
                        </div>

                        <!-- Zoom controls -->
                        <div class="control-group" role="group" aria-labelledby="zoom-settings-label">
                            <div class="control-group-label" id="zoom-settings-label">Zoom Settings</div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="zoom-rate-input">Click zoom rate:</label>
                                <input type="range" id="zoom-rate-input" min="-3" max="5" step="any" value="1" aria-label="Adjust click zoom rate" aria-valuemin="-3" aria-valuemax="5" aria-valuenow="1">
                            </div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="scroll-zoom-rate-input">Scroll zoom rate:</label>
                                <input type="range" id="scroll-zoom-rate-input" min="-3" max="5" step="any" value="1" aria-label="Adjust scroll zoom rate" aria-valuemin="-3" aria-valuemax="5" aria-valuenow="1">
                            </div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="click-zoom-toggle">Click to Zoom:</label>
                                <input type="checkbox" id="click-zoom-toggle" aria-label="Toggle click to zoom">
                            </div>
                        </div>
                        
                        <!-- Position controls -->
                        <div class="control-group" role="group" aria-labelledby="position-controls-label">
                            <div class="control-group-label" id="position-controls-label">Position Controls</div>
                            <div class="spacer-1"></div>
                            <div class="file-upload-container">
                                <input type="file" id="file-input" aria-label="Select position file">
                                <label for="file-input" id="position-file-label" class="file-upload-label" tabindex="0">
                                    Select position file
                                </label>
                            </div>
                            <div class="spacer-1"></div>
                            <button id="save-offset" aria-label="Save current position">Save Position</button>
                        </div>
                    </div>
                    
                    <div class="canvas-container" role="region" aria-label="Canvas display area">
                        <slot></slot>
                        
                        <!-- Drag and drop overlay -->
                        <div class="drag-drop-overlay" id="drag-drop-overlay" role="region" aria-label="Drag and drop area">
                            <div class="drag-drop-content">
                                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" aria-hidden="true">
                                    <path d="M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96zM14 13v4h-4v-4H7l5-5 5 5h-3z"/>
                                </svg>
                                <div class="drag-drop-title">Drop image to search</div>
                                <div class="drag-drop-desc">Drop your image file here to search for it</div>
                            </div>
                        </div>
                        
                        <!-- Fullscreen toggle button -->
                        <label for="fullscreen-toggle" class="fullscreen-toggle-label" aria-label="Toggle fullscreen" tabindex="0">
                            <svg class="expand-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                                <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/>
                            </svg>
                            <svg class="collapse-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
                                <path d="M5 16h3v3h2v-5H5v2zm3-8H5v2h5V5H8v3zm6 11h2v-3h3v-2h-5v5zm2-11V5h-2v5h5V8h-3z"/>
                            </svg>
                        </label>
                    </div>
                </div>
            </div>
        `;

        // Bind event handlers
        this.bindEventHandlers();
        this.attachEventListeners();
    }

    bindEventHandlers() {
        /** @type {Function} */
        this.handleClickZoomToggleChange = () => {
            const clickZoomToggle =
                this.shadowRoot.getElementById("click-zoom-toggle");
            this.canvasComponents.forEach((component) => {
                component.clickZoom = clickZoomToggle.checked;
            });
        };

        /** @type {Function} */
        this.handleZoomRateInput = () => {
            const zoomRateInput =
                this.shadowRoot.getElementById("zoom-rate-input");
            this.canvasComponents.forEach((component) => {
                component.clickZoomRate = zoomRateInput.value;
            });
            // Update ARIA value for accessibility
            zoomRateInput.setAttribute("aria-valuenow", zoomRateInput.value);
        };

        /** @type {Function} */
        this.handleScrollZoomRateInput = () => {
            const scrollZoomRateInput = this.shadowRoot.getElementById(
                "scroll-zoom-rate-input"
            );
            this.canvasComponents.forEach((component) => {
                component.scrollZoomRate = scrollZoomRateInput.value;
            });
            // Update ARIA value for accessibility
            scrollZoomRateInput.setAttribute(
                "aria-valuenow",
                scrollZoomRateInput.value
            );
        };

        /**
         * @type {Function}
         * @param {Event} event
         */
        this.handleFindImageInputChange = (event) => {
            if (event.target.files && event.target.files.length > 0) {
                const file = event.target.files[0];
                this.processImageFile(file);
                event.target.value = "";
            }
        };

        /**
         * @type {Function}
         * @param {Event} event
         */
        this.handlePositionFileInputChange = (event) => {
            if (event.target.files && event.target.files.length > 0) {
                const file = event.target.files[0];

                this.canvasComponents.forEach((component) => {
                    component.loadFile(file);
                });

                event.target.value = "";
            }
        };

        /** @type {Function} */
        this.handleSaveOffset = () => {
            this.canvasComponents.forEach((component) => {
                component.savePosition();
            });
        };

        /** @type {Function} */
        this.handleSaveImage = () => {
            const resolution = parseInt(
                this.shadowRoot.getElementById("save-image-resolution").value,
                10
            );

            this.canvasComponents.forEach((component) => {
                component.saveImage(resolution);
            });
        };

        /**
         * @type {Function}
         * @param {Event} event
         */
        this.handleFullscreenChange = (event) => {
            if (event.target.checked) {
                this.setAttribute("fake-fullscreen", "");
                this.setAttribute("aria-expanded", "true");
            } else {
                this.removeAttribute("fake-fullscreen");
                this.setAttribute("aria-expanded", "false");
            }
        };

        /**
         * @type {Function}
         * @param {DragEvent} event
         */
        this.handleDragEnter = (event) => {
            event.preventDefault();
            event.stopPropagation();
            this.isDragging = true;
            this.shadowRoot
                .getElementById("drag-drop-overlay")
                .classList.add("active");
        };

        /**
         * @type {Function}
         * @param {DragEvent} event
         */
        this.handleDragOver = (event) => {
            event.preventDefault();
            event.stopPropagation();
        };

        /**
         * @type {Function}
         * @param {DragEvent} event
         */
        this.handleDragLeave = (event) => {
            event.preventDefault();
            event.stopPropagation();

            const rect = this.getBoundingClientRect();
            const x = event.clientX;
            const y = event.clientY;

            if (
                x <= rect.left ||
                x >= rect.right ||
                y <= rect.top ||
                y >= rect.bottom
            ) {
                this.isDragging = false;
                this.shadowRoot
                    .getElementById("drag-drop-overlay")
                    .classList.remove("active");
            }
        };

        /**
         * @type {Function}
         * @param {DragEvent} event
         */
        this.handleDrop = (event) => {
            event.preventDefault();
            event.stopPropagation();

            this.isDragging = false;
            this.shadowRoot
                .getElementById("drag-drop-overlay")
                .classList.remove("active");

            if (
                event.dataTransfer.files &&
                event.dataTransfer.files.length > 0
            ) {
                const file = event.dataTransfer.files[0];

                if (file.type.startsWith("image/")) {
                    this.processImageFile(file);
                    return;
                }
            }

            this.tryExtractImageFromHtml(event.dataTransfer);
        };

        /**
         * @type {Function}
         * @param {KeyboardEvent} event
         */
        this.handleKeyDown = (event) => {
            // Handle keyboard events for custom controls
            if (
                event.target.classList.contains("menu-toggle-label") ||
                event.target.classList.contains("fullscreen-toggle-label") ||
                event.target.classList.contains("file-upload-label")
            ) {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    event.target.click();
                }
            }
        };

        /**
         * @type {Function}
         * @param {DataTransfer} dataTransfer
         */
        this.tryExtractImageFromHtml = (dataTransfer) => {
            const html = dataTransfer.getData("text/html");

            if (html) {
                const parser = new DOMParser();
                const doc = parser.parseFromString(html, "text/html");

                const img = doc.querySelector("img");

                if (img && img.src) {
                    this.fetchImageFromUrl(img.src);
                }
            }
        };

        /**
         * @type {Function}
         * @param {string} url
         */
        this.fetchImageFromUrl = (url) => {
            const fullUrl = new URL(url, window.location.href).href;

            fetch(fullUrl)
                .then((response) => {
                    if (!response.ok) {
                        throw new Error(
                            `Failed to fetch image: ${response.status} ${response.statusText}`
                        );
                    }
                    return response.blob();
                })
                .then((blob) => {
                    const fileName =
                        fullUrl.split("/").pop() || "dragged-image.jpg";
                    const file = new File([blob], fileName, {
                        type: blob.type,
                    });

                    this.processImageFile(file);
                })
                .catch((error) => {
                    console.error("Error fetching image:", error);
                });
        };
    }

    /**
     * @param {File} file
     */
    processImageFile(file) {
        const resolution = parseInt(
            this.shadowRoot.getElementById("image-resolution").value,
            10
        );

        this.canvasComponents.forEach((component) => {
            component.searchImage(file, resolution);
        });
    }

    attachEventListeners() {
        if (this._listenersAttached || !this.shadowRoot) return;

        const shadow = this.shadowRoot;

        shadow
            .getElementById("click-zoom-toggle")
            ?.addEventListener("change", this.handleClickZoomToggleChange);

        shadow
            .getElementById("zoom-rate-input")
            ?.addEventListener("input", this.handleZoomRateInput);
        shadow
            .getElementById("scroll-zoom-rate-input")
            ?.addEventListener("input", this.handleScrollZoomRateInput);

        shadow
            .getElementById("find-image-input")
            ?.addEventListener("change", this.handleFindImageInputChange);

        shadow
            .getElementById("file-input")
            ?.addEventListener("change", this.handlePositionFileInputChange);

        shadow
            .getElementById("save-offset")
            ?.addEventListener("click", this.handleSaveOffset);
        shadow
            .getElementById("save-image-button")
            ?.addEventListener("click", this.handleSaveImage);

        shadow
            .getElementById("fullscreen-toggle")
            ?.addEventListener("change", this.handleFullscreenChange);

        // Add keyboard event listeners for custom controls
        shadow.addEventListener("keydown", this.handleKeyDown);

        const canvasContainer = shadow.querySelector(".canvas-container");
        if (canvasContainer) {
            canvasContainer.addEventListener(
                "dragenter",
                this.handleDragEnter.bind(this)
            );
            canvasContainer.addEventListener(
                "dragover",
                this.handleDragOver.bind(this)
            );
            canvasContainer.addEventListener(
                "dragleave",
                this.handleDragLeave.bind(this)
            );
            canvasContainer.addEventListener(
                "drop",
                this.handleDrop.bind(this)
            );
        }

        this._listenersAttached = true;
    }

    /**
     * Called when element is added to the DOM
     */
    connectedCallback() {
        if (this.parentElement) {
            this.canvasComponents = Array.from(
                this.parentElement.querySelectorAll("canvas-component")
            );
        }

        // Set initial ARIA expanded state
        this.setAttribute("aria-expanded", "false");
    }
}

// Register the custom element
customElements.define("canvas-component-controls", CanvasComponentControls);
