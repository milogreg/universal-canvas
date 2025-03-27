"use strict";

class CanvasComponentControls extends HTMLElement {
    constructor() {
        super();

        // Core properties
        this.canvasComponents = [];
        this._listenersAttached = false;

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
            </style>
            
            <!-- Menu toggle checkbox -->
            <input type="checkbox" id="menu-toggle">
            
            <!-- Fullscreen toggle checkbox -->
            <input type="checkbox" id="fullscreen-toggle">
            
            <div class="component-container">
                <!-- Menu toggle button -->
                <label for="menu-toggle" class="menu-toggle-label" aria-label="Toggle menu">
                    <span>Menu</span>
                    <svg class="menu-arrow" viewBox="0 0 24 12" xmlns="http://www.w3.org/2000/svg">
                        <path d="M3 6H18M13 1L18 6L13 11" stroke="currentColor" stroke-width="2" stroke-linecap="butt" stroke-linejoin="miter" fill="none"/>
                    </svg>
                </label>
                
                <div class="layout-container">
                    <div class="controls-container">
                        <!-- Zoom controls -->
                        <div class="control-group">
                            <label class="control-group-label">Zoom Settings</label>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="zoom-rate-input">Click zoom rate:</label>
                                <input type="range" id="zoom-rate-input" min="-3" max="5" step="any" value="1">
                            </div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="scroll-zoom-rate-input">Scroll zoom rate:</label>
                                <input type="range" id="scroll-zoom-rate-input" min="-3" max="5" step="any" value="1">
                            </div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="click-zoom-toggle">Click to Zoom:</label>
                                <input type="checkbox" id="click-zoom-toggle">
                            </div>
                        </div>
                        
                        <!-- Image search -->
                        <div class="control-group">
                            <label class="control-group-label">Image Search</label>
                            <div class="spacer-1"></div>
                            <div class="file-upload-container">
                                <input type="file" id="find-image-input" accept="image/*">
                                <label for="find-image-input" id="file-upload-label" class="file-upload-label">
                                    Select an image to search
                                </label>
                            </div>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="image-resolution">Resolution:</label>
                                <select id="image-resolution">
                                    <option value="64">64px</option>
                                    <option value="128">128px</option>
                                    <option value="256">256px</option>
                                    <option value="512">512px</option>
                                    <option value="1024" selected>1024px</option>
                                    <option value="2048">2048px</option>
                                </select>
                            </div>
                        </div>
                        
                        <!-- Position controls -->
                        <div class="control-group">
                            <label class="control-group-label">Position Controls</label>
                            <div class="spacer-1"></div>
                            <div class="file-upload-container">
                                <input type="file" id="file-input">
                                <label for="file-input" id="position-file-label" class="file-upload-label">
                                    Select position file
                                </label>
                            </div>
                            <div class="spacer-1"></div>
                            <button id="save-offset">Save Position</button>
                        </div>
                        
                        <!-- Save image -->
                        <div class="control-group">
                            <label class="control-group-label">Save Image</label>
                            <div class="spacer-1"></div>
                            <div>
                                <label for="save-image-resolution">Resolution:</label>
                                <select id="save-image-resolution">
                                    <option value="64">64px</option>
                                    <option value="128">128px</option>
                                    <option value="256">256px</option>
                                    <option value="512">512px</option>
                                    <option value="1024" selected>1024px</option>
                                    <option value="2048">2048px</option>
                                </select>
                            </div>
                            <div class="spacer-1"></div>
                            <button id="save-image-button">Save Image</button>
                        </div>
                    </div>
                    
                    <div class="canvas-container">
                        <slot></slot>
                        
                        <!-- Fullscreen toggle button -->
                        <label for="fullscreen-toggle" class="fullscreen-toggle-label" aria-label="Toggle fullscreen">
                            <svg class="expand-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                                <path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/>
                            </svg>
                            <svg class="collapse-icon" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
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

    // Bind all event handlers at once
    bindEventHandlers() {
        this.handleClickZoomToggleChange = () => {
            const clickZoomToggle =
                this.shadowRoot.getElementById("click-zoom-toggle");
            this.canvasComponents.forEach((component) => {
                component.clickZoom = clickZoomToggle.checked;
            });
        };

        this.handleZoomRateInput = () => {
            const zoomRateInput =
                this.shadowRoot.getElementById("zoom-rate-input");
            this.canvasComponents.forEach((component) => {
                component.clickZoomRate = zoomRateInput.value;
            });
        };

        this.handleScrollZoomRateInput = () => {
            const scrollZoomRateInput = this.shadowRoot.getElementById(
                "scroll-zoom-rate-input"
            );
            this.canvasComponents.forEach((component) => {
                component.scrollZoomRate = scrollZoomRateInput.value;
            });
        };

        this.handleFindImageInputChange = (event) => {
            if (event.target.files && event.target.files.length > 0) {
                const file = event.target.files[0];
                const resolution = parseInt(
                    this.shadowRoot.getElementById("image-resolution").value,
                    10
                );

                this.canvasComponents.forEach((component) => {
                    component.searchImage(file, resolution);
                });

                event.target.value = "";
            }
        };

        this.handlePositionFileInputChange = (event) => {
            if (event.target.files && event.target.files.length > 0) {
                const file = event.target.files[0];

                this.canvasComponents.forEach((component) => {
                    component.loadFile(file);
                });

                event.target.value = "";
            }
        };

        this.handleSaveOffset = () => {
            this.canvasComponents.forEach((component) => {
                component.savePosition();
            });
        };

        this.handleSaveImage = () => {
            const resolution = parseInt(
                this.shadowRoot.getElementById("save-image-resolution").value,
                10
            );

            this.canvasComponents.forEach((component) => {
                component.saveImage(resolution);
            });
        };

        // Add fullscreen handler
        this.handleFullscreenChange = (event) => {
            if (event.target.checked) {
                this.setAttribute("fake-fullscreen", "");
            } else {
                this.removeAttribute("fake-fullscreen");
            }
        };
    }

    // Attach event listeners
    attachEventListeners() {
        if (this._listenersAttached || !this.shadowRoot) return;

        const shadow = this.shadowRoot;

        // Click zoom toggle
        shadow
            .getElementById("click-zoom-toggle")
            ?.addEventListener("change", this.handleClickZoomToggleChange);

        // Zoom rates
        shadow
            .getElementById("zoom-rate-input")
            ?.addEventListener("input", this.handleZoomRateInput);
        shadow
            .getElementById("scroll-zoom-rate-input")
            ?.addEventListener("input", this.handleScrollZoomRateInput);

        // Image search
        shadow
            .getElementById("find-image-input")
            ?.addEventListener("change", this.handleFindImageInputChange);

        // Position file
        shadow
            .getElementById("file-input")
            ?.addEventListener("change", this.handlePositionFileInputChange);

        // Buttons
        shadow
            .getElementById("save-offset")
            ?.addEventListener("click", this.handleSaveOffset);
        shadow
            .getElementById("save-image-button")
            ?.addEventListener("click", this.handleSaveImage);

        // Fullscreen toggle
        shadow
            .getElementById("fullscreen-toggle")
            ?.addEventListener("change", this.handleFullscreenChange);

        this._listenersAttached = true;
    }

    // Called when element is added to the DOM
    connectedCallback() {
        if (this.parentElement) {
            this.canvasComponents = Array.from(
                this.parentElement.querySelectorAll("canvas-component")
            );
        }
    }
}

// Register the custom element
customElements.define("canvas-component-controls", CanvasComponentControls);
