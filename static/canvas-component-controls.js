"use strict";

class CanvasComponentControls extends HTMLElement {
    constructor() {
        super();

        // Initialize canvas components array
        this.canvasComponents = [];

        // Flag to track if event listeners have been attached
        this._listenersAttached = false;

        // Create the shadow DOM
        const shadow = this.attachShadow({ mode: "open" });

        // Create styles and HTML structure using innerHTML
        shadow.innerHTML = /*html*/ `
            <style>
                /* CSS Variables */
                :host {
                    --bg-button:rgb(59, 130, 163);
                    --bg-button-hover: rgb(43, 103, 131);
                    --bg-primary: #eeeeee;
                    --bg-secondary: #f5f5f5;
                    --border-color: rgb(160, 160, 160);
                    --text-primary: #222222;
                    --color-button: rgb(245, 245, 245);
                    --shadow: 0 0.125rem 0.25rem rgba(0, 0, 0, 0.25);
                    --transition: all 0.1s ease;
                    --border-radius: 0.25rem;
                    --menu-width: 20rem;
                    --drop-zone-bg: #f5f5f5;
                    --drop-zone-bg-active: #e0e0e0;
                    --drop-zone-border: #ccc;
                    --drop-zone-border-active: #999;
                    --success-color: #2e7d32;
                }

                /* Dark Mode Support */
                @media (prefers-color-scheme: dark) {
                    :host {
                        --bg-button:rgb(43, 103, 131);
                        --bg-button-hover: rgb(32, 77, 99);
                        --bg-primary: rgb(34, 34, 34);
                        --bg-secondary: rgb(46, 46, 46);
                        --border-color: rgb(137, 137, 137);
                        --text-primary: rgb(231, 231, 231);
                        --shadow: 0 0.125rem 0.25rem rgba(0, 0, 0, 0.4);
                        --drop-zone-bg: rgb(46, 46, 46);
                        --drop-zone-bg-active: rgb(60, 60, 60);
                        --drop-zone-border: rgb(100, 100, 100);
                        --drop-zone-border-active: rgb(150, 150, 150);
                        --success-color: #4caf50;
                    }
                }
                
                /* Base Layout */
                :host {
                    color: var(--text-primary);
                    box-sizing: border-box;
                    display: block;
                    height: 60rem;
                    max-width: 100%;
                    max-height: 100%;
                    overflow: hidden;
                    position: relative;
                    transition: var(--transition);
                    container-type: inline-size; /* Set up container query context */
                }
                
                /* New fullscreen container */
                .component-container {
                    width: 100%;
                    height: 100%;
                    position: relative;
                    transition: var(--transition);
                }
                
                /* Fullscreen State applied to container */
                #fullscreen-toggle:checked ~ .component-container {
                    position: fixed;
                    top: 0;
                    left: 0;
                    min-width: 100dvw;
                    min-height: 100dvh;
                    z-index: 9999;
                    margin: 0;
                    padding: 0;
                    border: none;
                }
                
                .layout-container {
                    width: 100%;
                    height: 100%;
                    display: flex;
                    position: relative;
                }
                
                .controls-container {
                    background-color: var(--bg-primary);
                    box-sizing: border-box;
                    height: 100%;
                    display: flex;
                    flex-direction: column;
                    gap: 1rem;
                    max-width: min(var(--menu-width), 100%);
                    overflow-y: auto;
                    padding: 1rem;
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
                
                /* Update fullscreen selector to target container with checkbox */
                #fullscreen-toggle:checked ~ .component-container .controls-container {
                    height: 100vh;
                }
                
                /* Menu Toggle */
                #menu-toggle {
                    opacity: 0;
                    position: absolute;
                    height: 0;
                    width: 0;
                }
                
                /* Fullscreen Toggle - hidden like menu toggle */
                #fullscreen-toggle {
                    opacity: 0;
                    position: absolute;
                    height: 0;
                    width: 0;
                }
                
                /* Menu button styling with text and arrow - tighter spacing */
                .menu-toggle-label {
                    background-color: var(--bg-button);
                    border-radius: var(--border-radius);
                    box-shadow: var(--shadow);
                    color: var(--color-button);
                    cursor: pointer;
                    padding: 0.35rem 0.5rem; /* Reduced padding */
                    position: absolute;
                    left: 1rem; 
                    top: 1rem; 
                    transition: var(--transition);
                    display: none; /* Hidden by default */
                    align-items: center;
                    gap: 0.25rem; /* Tighter gap between elements */
                    z-index: 200;
                    line-height: 1.2rem;
              
                    font-weight: 500;
                }
                
                /* Menu text and arrow styling */
                .menu-text {
                    display: inline-block;
                    margin-right: 0.25rem; /* Reduced spacing */
                }
                
                /* SVG Arrow icon that rotates */
                .menu-arrow {
                    display: inline-block;
                    width: 1.25rem;
                    height: 0.75rem;
                    color: var(--color-button);
                    vertical-align: middle;
                    margin-left: 0.125rem;
                    transition: transform 0.2s ease;
                }
                
                /* Rotate arrow when menu is open */
                #menu-toggle:checked ~ .component-container .menu-arrow {
                    transform: rotate(180deg);
                }
                
                /* Container query for narrow layouts */
                @container (max-width: 60rem) {
                    .component-container .menu-toggle-label {
                        display: flex;
                    }
                    
                    .controls-container {
                        border-right: 0.0625rem solid var(--border-color);
                        box-shadow: 0.125rem 0 0.3125rem rgba(0, 0, 0, 0.1);
                        position: absolute;
                        transform: translateX(-110%);
                        z-index: 150; /* Ensure menu appears below the toggle button */
                        padding-top: 3.9rem; 
                    }
                }
                
                /* Only show menu toggle in fullscreen mode regardless of width */
                #fullscreen-toggle:checked ~ .component-container .menu-toggle-label {
                    display: flex;
                }
                
                .menu-toggle-label:hover {
                    background-color: var(--bg-button-hover);
                }
                
                /* Fullscreen Button - now a label for checkbox */
                .fullscreen-toggle-label {
                    background-color: var(--bg-button);
                    border: none;
                    border-radius: var(--border-radius);
                    bottom: 1rem;
                    box-shadow: var(--shadow);
                    color: var(--color-button);
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    height: 2rem;
                    padding: 0.3rem;
                    position: absolute;
                    right: 1rem;
                    transition: var(--transition);
                    width: 2rem;
                    z-index: 100;
                }
                
                .fullscreen-toggle-label:hover {
                    background-color: var(--bg-button-hover);
                }
                
                .fullscreen-toggle-label svg {
                    height: 100%;
                    width: 100%;
                    fill: currentColor;
                }
                
                /* Icon States - update to use checkbox */
                #fullscreen-toggle:checked ~ .component-container .expand-icon,
                #fullscreen-toggle:not(:checked) ~ .component-container .collapse-icon {
                    display: none;
                }
                
                /* Fullscreen state for controls container */
                #fullscreen-toggle:checked ~ .component-container .controls-container {
                    border-right: 0.0625rem solid var(--border-color);
                    box-shadow: 0.125rem 0 0.3125rem rgba(0, 0, 0, 0.1);
                    position: absolute;
                    transform: translateX(-110%);
                    z-index: 150;
                    padding-top: 3.9rem;
                }
                
                /* Show menu when checkbox is checked */
                #menu-toggle:checked ~ .component-container .layout-container .controls-container {
                    transform: translateX(0);
                }
                
                /* Control Elements */
                .control-group {
                    background-color: var(--bg-secondary);
                    border: 0.0625rem solid var(--border-color);
                    border-radius: var(--border-radius);
                    padding: 1rem;
                }
                
                .control-group h3 {
                    font-size: 1rem;
                    margin: 0 0 0.5rem;
                }
                
                /* Form Elements */
                table, input[type="range"] {
                    width: 100%;
                }
                
                label {
                    display: inline-block;
                    margin-right: 0.5rem;
                }
                
                .resolution-select-container {
                    display: flex;
                    align-items: center;
                    margin-top: 0.75rem;
                }
                
                .resolution-select {
                    flex: 1;
                    padding: 0.35rem;
                    border-radius: var(--border-radius);
                    border: 1px solid var(--border-color);
                    background-color: var(--bg-primary);
                    color: var(--text-primary);
                    font-size: 0.85rem;
                }
                
                /* Custom File Input and Drop Zone */
                .file-upload-container {
                    position: relative;
                    margin-top: 0.5rem;
                }
                
                .file-upload-container input[type="file"] {
                    position: absolute;
                    width: 0.1px;
                    height: 0.1px;
                    opacity: 0;
                    overflow: hidden;
                    z-index: -1;
                }
                
                .file-upload-label {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    border: 0.125rem dashed var(--drop-zone-border);
                    border-radius: var(--border-radius);
                    background-color: transparent;
                    color: var(--text-primary);
                    cursor: pointer;
                    padding: 0.75rem 0.5rem;
                    text-align: center;
                    transition: var(--transition);
                    width: 100%;
                    box-sizing: border-box;
                }
                
                .file-upload-label:hover {
                    background-color: var(--drop-zone-bg);
                    border-color: var(--border-color);
                }
                
                .file-upload-label:active {
                    background-color: var(--bg-secondary);
                    transform: translateY(1px);
                }
                
                .file-upload-label.drag-active {
                    background-color: var(--drop-zone-bg-active);
                    border-color: var(--drop-zone-border-active);
                    border-style: solid;
                }
                
                .file-upload-icon {
                    margin-bottom: 0.25rem;
                    width: 1.5rem;
                    height: 1.5rem;
                    fill: var(--text-primary);
                    opacity: 0.7;
                }
                
                .file-upload-text {
                    font-size: 0.875rem;
                    margin-bottom: 0.125rem;
                }
                
                .file-upload-hint {
                    font-size: 0.75rem;
                    opacity: 0.8;
                }
                
                .file-feedback {
                    display: block;
                    margin-top: 0.25rem;
                    font-size: 0.75rem;
                    color: var(--success-color);
                    font-weight: 500;
                }
                
                /* Hide default text when file is selected */
                .file-upload-label.has-file .file-upload-text,
                .file-upload-label.has-file .file-upload-hint {
                    display: none;
                }
                
                /* Buttons */
                button {
                    background-color: var(--bg-button);
                    border: none;
                    border-radius: var(--border-radius);
                    color: white;
                    cursor: pointer;
                    margin-top: 0.5rem;
                    padding: 0.5rem 1rem;
                    transition: var(--transition);
                }
                
                button:hover {
                    background-color: var(--bg-button-hover);
                }

                /* Slot */
                ::slotted(canvas-component) {
                    flex-grow: 1;
                    width: 100%;
                }
            </style>
            
            <!-- Menu toggle for narrow layouts -->
            <input type="checkbox" id="menu-toggle">
            
            <!-- Fullscreen toggle checkbox -->
            <input type="checkbox" id="fullscreen-toggle">
            
            <!-- New container for fullscreen mode -->
            <div class="component-container">
                <label for="menu-toggle" class="menu-toggle-label" aria-label="Toggle menu">
                    <span class="menu-text">Menu</span>
                    <svg class="menu-arrow" viewBox="0 0 24 12" xmlns="http://www.w3.org/2000/svg" width="20" height="12">
                        <path d="M3 6H18M13 1L18 6L13 11" stroke="currentColor" stroke-width="2" stroke-linecap="butt" stroke-linejoin="miter" fill="none"/>
                    </svg>
                </label>
                
                <div class="layout-container">
                    <div class="controls-container">
                        <!-- Zoom controls -->
                        <div class="control-group">
                            <h3>Zoom Settings</h3>
                            <table>
                                <tr>
                                    <td>
                                        <label for="zoom-rate-input">Click zoom rate:</label>
                                    </td>
                                    <td>
                                        <input type="range" id="zoom-rate-input" min="-3" max="5" step="any" value="1">
                                    </td>
                                </tr>
                                <tr>
                                    <td>
                                        <label for="scroll-zoom-rate-input">Scroll zoom rate:</label>
                                    </td>
                                    <td>
                                        <input type="range" id="scroll-zoom-rate-input" min="-3" max="5" step="any" value="1">
                                    </td>
                                </tr>
                            </table>
                            <div>
                                <label for="click-zoom-toggle">Click to Zoom:</label>
                                <input type="checkbox" id="click-zoom-toggle">
                            </div>
                        </div>
                        
                        <!-- Image search controls -->
                        <div class="control-group">
                            <h3>Image Search</h3>
                            <div class="file-upload-container">
                                <input type="file" id="find-image-input" accept="image/*">
                                <label for="find-image-input" id="file-upload-label" class="file-upload-label">
                                    <svg class="file-upload-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                                        <path d="M5 20h14v-2H5v2zm0-10h4v6h6v-6h4l-7-7-7 7z"/>
                                    </svg>
                                    <span class="file-upload-text">Select an image</span>
                                    <span class="file-upload-hint">Click or drag & drop</span>
                                </label>
                            </div>
                            <div class="resolution-select-container">
                                <label for="image-resolution">Resolution:</label>
                                <select id="image-resolution" class="resolution-select">
                                    <option value="64">64px</option>
                                    <option value="128">128px</option>
                                    <option value="256">256px</option>
                                    <option value="512">512px</option>
                                    <option value="1024" selected>1024px</option>
                                    <option value="2048">2048px</option>
                                </select>
                            </div>
                        </div>
                        
                        <!-- File controls -->
                        <div class="control-group">
                            <h3>Position Controls</h3>
                            <div class="file-upload-container">
                                <input type="file" id="file-input">
                                <label for="file-input" id="position-file-label" class="file-upload-label">
                                    <svg class="file-upload-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
                                        <path d="M5 20h14v-2H5v2zm0-10h4v6h6v-6h4l-7-7-7 7z"/>
                                    </svg>
                                    <span class="file-upload-text">Select position file</span>
                                    <span class="file-upload-hint">Click or drag & drop</span>
                                </label>
                            </div>
                            <div>
                                <button id="save-offset">Save Position</button>
                            </div>
                        </div>
                        
                        <!-- Save Image controls -->
                        <div class="control-group">
                            <h3>Save Image</h3>
                            <div class="resolution-select-container">
                                <label for="save-image-resolution">Resolution:</label>
                                <select id="save-image-resolution" class="resolution-select">
                                    <option value="64">64px</option>
                                    <option value="128">128px</option>
                                    <option value="256">256px</option>
                                    <option value="512">512px</option>
                                    <option value="1024" selected>1024px</option>
                                    <option value="2048">2048px</option>
                                </select>
                            </div>
                            <div>
                                <button id="save-image-button">Save Image</button>
                            </div>
                        </div>
                    </div>
                    
                    <div class="canvas-container">
                        <slot></slot>
                        
                        <!-- Fullscreen toggle label for checkbox -->
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

        // Define event handlers in the constructor
        this.handleClickZoomToggleChange =
            this.handleClickZoomToggleChange.bind(this);
        this.handleZoomRateInput = this.handleZoomRateInput.bind(this);
        this.handleScrollZoomRateInput =
            this.handleScrollZoomRateInput.bind(this);
        this.handleFindImageInputChange =
            this.handleFindImageInputChange.bind(this);
        this.handleDropZoneDragover = this.handleDropZoneDragover.bind(this);
        this.handleDropZoneDragleave = this.handleDropZoneDragleave.bind(this);
        this.handleDropZoneDrop = this.handleDropZoneDrop.bind(this);
        this.handlePositionFileInputChange =
            this.handlePositionFileInputChange.bind(this);
        this.handlePositionDropZoneDragover =
            this.handlePositionDropZoneDragover.bind(this);
        this.handlePositionDropZoneDragleave =
            this.handlePositionDropZoneDragleave.bind(this);
        this.handlePositionDropZoneDrop =
            this.handlePositionDropZoneDrop.bind(this);
        this.handleSaveOffset = this.handleSaveOffset.bind(this);
        this.handleFullscreenChange = this.handleFullscreenChange.bind(this);
        this.handleSaveImage = this.handleSaveImage.bind(this);

        // Attach the event listeners once after shadow DOM is created
        this.attachEventListeners();
    }

    // Event handler methods defined once per instance
    handleClickZoomToggleChange() {
        const clickZoomToggle =
            this.shadowRoot.getElementById("click-zoom-toggle");
        this.canvasComponents.forEach((component) => {
            component.clickZoom = clickZoomToggle.checked;
        });
    }

    handleZoomRateInput() {
        const zoomRateInput = this.shadowRoot.getElementById("zoom-rate-input");
        this.canvasComponents.forEach((component) => {
            component.clickZoomRate = zoomRateInput.value;
        });
    }

    handleScrollZoomRateInput() {
        const scrollZoomRateInput = this.shadowRoot.getElementById(
            "scroll-zoom-rate-input"
        );
        this.canvasComponents.forEach((component) => {
            component.scrollZoomRate = scrollZoomRateInput.value;
        });
    }

    handleFindImageInputChange(event) {
        if (event.target.files && event.target.files.length > 0) {
            const file = event.target.files[0];
            const fileUploadLabel =
                this.shadowRoot.getElementById("file-upload-label");
            const resolutionSelect =
                this.shadowRoot.getElementById("image-resolution");
            const resolution = parseInt(resolutionSelect.value, 10);

            // Add the "has-file" class to hide default text
            fileUploadLabel.classList.add("has-file");

            // Find existing feedback element or create a new one
            let feedbackElement =
                fileUploadLabel.querySelector(".file-feedback");
            if (!feedbackElement) {
                feedbackElement = document.createElement("span");
                feedbackElement.className = "file-feedback";
                fileUploadLabel.appendChild(feedbackElement);
            }

            // Update the feedback text
            feedbackElement.textContent = `File selected: ${file.name}`;

            this.canvasComponents.forEach((component) => {
                component.searchImage(file, resolution);
            });

            // Reset file input value to allow selecting the same file again
            event.target.value = "";
        }
    }

    handleDropZoneDragover(event) {
        event.preventDefault();
        const fileUploadLabel =
            this.shadowRoot.getElementById("file-upload-label");
        fileUploadLabel.classList.add("drag-active");
    }

    handleDropZoneDragleave() {
        const fileUploadLabel =
            this.shadowRoot.getElementById("file-upload-label");
        fileUploadLabel.classList.remove("drag-active");
    }

    handleDropZoneDrop(event) {
        event.preventDefault();
        const fileUploadLabel =
            this.shadowRoot.getElementById("file-upload-label");
        const resolutionSelect =
            this.shadowRoot.getElementById("image-resolution");
        const resolution = parseInt(resolutionSelect.value, 10);
        const fileInput = this.shadowRoot.getElementById("find-image-input");

        fileUploadLabel.classList.remove("drag-active");

        if (event.dataTransfer.files && event.dataTransfer.files.length > 0) {
            const file = event.dataTransfer.files[0];

            // Add the "has-file" class to hide default text
            fileUploadLabel.classList.add("has-file");

            // Find existing feedback element or create a new one
            let feedbackElement =
                fileUploadLabel.querySelector(".file-feedback");
            if (!feedbackElement) {
                feedbackElement = document.createElement("span");
                feedbackElement.className = "file-feedback";
                fileUploadLabel.appendChild(feedbackElement);
            }

            // Update the feedback text
            feedbackElement.textContent = `File selected: ${file.name}`;

            this.canvasComponents.forEach((component) => {
                component.searchImage(file, resolution);
            });

            // Reset file input value to allow selecting the same file again
            fileInput.value = "";
        }
    }

    // Position file handlers
    handlePositionFileInputChange(event) {
        if (event.target.files && event.target.files.length > 0) {
            const file = event.target.files[0];
            const positionFileLabel = this.shadowRoot.getElementById(
                "position-file-label"
            );

            // Add the "has-file" class to hide default text
            positionFileLabel.classList.add("has-file");

            // Find existing feedback element or create a new one
            let feedbackElement =
                positionFileLabel.querySelector(".file-feedback");
            if (!feedbackElement) {
                feedbackElement = document.createElement("span");
                feedbackElement.className = "file-feedback";
                positionFileLabel.appendChild(feedbackElement);
            }

            // Update the feedback text
            feedbackElement.textContent = `File selected: ${file.name}`;

            // Process the file immediately (previously done by the Set Position button)
            this.canvasComponents.forEach((component) => {
                component.loadFile(file);
            });

            // Reset file input value to allow selecting the same file again
            event.target.value = "";
        }
    }

    handlePositionDropZoneDragover(event) {
        event.preventDefault();
        const positionFileLabel = this.shadowRoot.getElementById(
            "position-file-label"
        );
        positionFileLabel.classList.add("drag-active");
    }

    handlePositionDropZoneDragleave() {
        const positionFileLabel = this.shadowRoot.getElementById(
            "position-file-label"
        );
        positionFileLabel.classList.remove("drag-active");
    }

    handlePositionDropZoneDrop(event) {
        event.preventDefault();
        const positionFileLabel = this.shadowRoot.getElementById(
            "position-file-label"
        );
        const fileInput = this.shadowRoot.getElementById("file-input");

        positionFileLabel.classList.remove("drag-active");

        if (event.dataTransfer.files && event.dataTransfer.files.length > 0) {
            const file = event.dataTransfer.files[0];

            // Add the "has-file" class to hide default text
            positionFileLabel.classList.add("has-file");

            // Find existing feedback element or create a new one
            let feedbackElement =
                positionFileLabel.querySelector(".file-feedback");
            if (!feedbackElement) {
                feedbackElement = document.createElement("span");
                feedbackElement.className = "file-feedback";
                positionFileLabel.appendChild(feedbackElement);
            }

            // Update the feedback text
            feedbackElement.textContent = `File selected: ${file.name}`;

            // Process the file immediately
            this.canvasComponents.forEach((component) => {
                component.loadFile(file);
            });

            // Reset file input value to allow selecting the same file again
            fileInput.value = "";
        }
    }

    handleSaveOffset() {
        this.canvasComponents.forEach((component) => {
            component.savePosition();
        });
    }

    handleSaveImage() {
        const saveImageResolution = this.shadowRoot.getElementById(
            "save-image-resolution"
        );
        const resolution = parseInt(saveImageResolution.value, 10);

        this.canvasComponents.forEach((component) => {
            component.saveImage(resolution);
        });
    }

    handleFullscreenChange(event) {
        if (event.target.checked) {
            this.setAttribute("fake-fullscreen", "");
        } else {
            this.removeAttribute("fake-fullscreen");
        }
    }

    // Attach event listeners once
    attachEventListeners() {
        if (this._listenersAttached || !this.shadowRoot) return;

        const shadow = this.shadowRoot;

        // Click zoom toggle
        const clickZoomToggle = shadow.getElementById("click-zoom-toggle");
        if (clickZoomToggle) {
            clickZoomToggle.addEventListener(
                "change",
                this.handleClickZoomToggleChange
            );
        }

        // Click zoom rate
        const zoomRateInput = shadow.getElementById("zoom-rate-input");
        if (zoomRateInput) {
            zoomRateInput.addEventListener("input", this.handleZoomRateInput);
        }

        // Scroll zoom rate
        const scrollZoomRateInput = shadow.getElementById(
            "scroll-zoom-rate-input"
        );
        if (scrollZoomRateInput) {
            scrollZoomRateInput.addEventListener(
                "input",
                this.handleScrollZoomRateInput
            );
        }

        // Find image input
        const findImageInput = shadow.getElementById("find-image-input");
        if (findImageInput) {
            findImageInput.addEventListener(
                "change",
                this.handleFindImageInputChange
            );
        }

        // Find image drop zone (now the file upload label serves as drop zone)
        const fileUploadLabel = shadow.getElementById("file-upload-label");
        if (fileUploadLabel) {
            fileUploadLabel.addEventListener(
                "dragover",
                this.handleDropZoneDragover
            );
            fileUploadLabel.addEventListener(
                "dragleave",
                this.handleDropZoneDragleave
            );
            fileUploadLabel.addEventListener("drop", this.handleDropZoneDrop);
        }

        // Position file input
        const fileInput = shadow.getElementById("file-input");
        if (fileInput) {
            fileInput.addEventListener(
                "change",
                this.handlePositionFileInputChange
            );
        }

        // Position file drop zone
        const positionFileLabel = shadow.getElementById("position-file-label");
        if (positionFileLabel) {
            positionFileLabel.addEventListener(
                "dragover",
                this.handlePositionDropZoneDragover
            );
            positionFileLabel.addEventListener(
                "dragleave",
                this.handlePositionDropZoneDragleave
            );
            positionFileLabel.addEventListener(
                "drop",
                this.handlePositionDropZoneDrop
            );
        }

        // Save position
        const saveOffsetButton = shadow.getElementById("save-offset");
        if (saveOffsetButton) {
            saveOffsetButton.addEventListener("click", this.handleSaveOffset);
        }

        // Save image
        const saveImageButton = shadow.getElementById("save-image-button");
        if (saveImageButton) {
            saveImageButton.addEventListener("click", this.handleSaveImage);
        }

        const fullscreenToggle = shadow.getElementById("fullscreen-toggle");
        if (fullscreenToggle) {
            fullscreenToggle.addEventListener(
                "change",
                this.handleFullscreenChange
            );
        }

        this._listenersAttached = true;
    }

    connectedCallback() {
        // Only update the list of canvas components
        if (this.parentElement) {
            this.canvasComponents = Array.from(
                this.parentElement.querySelectorAll("canvas-component")
            );
        }
    }
}

// Define the custom element
customElements.define("canvas-component-controls", CanvasComponentControls);
