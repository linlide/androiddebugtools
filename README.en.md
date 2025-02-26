# Android UI Automatic Viewer

This tool provides a simple way to capture Android device UI interfaces and view and analyze UI structures interactively in a browser.

![Android UI Viewer Screenshot](resources/Screenshot%202025-02-26%20at%2014.53.45.png)

## Features

- Automatic capture of Android device screenshots
- Automatic retrieval of UI hierarchy (XML format)
- Generation of interactive HTML viewer with support for:
  - Tree view of UI structure
  - Detailed view of element attributes
  - Highlighting selected elements on the screenshot
  - Searching UI elements
  - Viewing raw XML content
  - Multi-language support (English/Chinese)
- Complete support for Chinese and Japanese characters
- Automatic handling of XML encoding issues
- Support for various device connection methods

## Requirements

- macOS or Linux system (Windows may require additional configuration)
- ADB (Android Debug Bridge) installed
- Android device with USB debugging enabled

## Environment Setup

### 1. Install Android SDK

If you haven't installed Android SDK yet, you can install it using the following methods:

#### macOS (using Homebrew):

```bash
brew install android-platform-tools
```

#### Linux:

```bash
sudo apt-get install android-tools-adb
```

Or download Android SDK from the official Android website, then set environment variables:

```bash
export ANDROID_SDK_ROOT=/path/to/android/sdk
export PATH=$PATH:$ANDROID_SDK_ROOT/platform-tools
```

### 2. Configure Device

1. Enable developer options on your Android device:
   - Go to Settings > About phone
   - Tap "Build number" 7 times to enable developer options
   - Return to Settings, enter the newly appeared "Developer options"
   - Enable "USB debugging"

2. Connect and authorize the device:
   - Connect the device to your computer using a USB cable
   - Confirm the USB debugging authorization prompt on the device

3. Verify device connection:
   ```bash
   adb devices
   ```
   You should see your device listed

## Usage

### Basic Usage

1. Ensure the script has execution permissions:
   ```bash
   chmod +x auto_view_ui.sh
   ```

2. Run the script:
   ```bash
   ./auto_view_ui.sh
   ```

3. The script will automatically:
   - Detect connected Android devices
   - Capture a screenshot
   - Retrieve the UI hierarchy
   - Create an HTML viewer
   - Open the viewer in your default browser

### HTML Viewer Usage

The HTML viewer provides the following features:

- **Language Selection**: Choose English or Chinese interface at the top
- **Tree Browsing**: Left panel displays the tree structure of UI elements
- **Element Details**: Click any element to view its detailed attributes
- **Element Highlighting**: Selected elements are highlighted on the screenshot
- **Search Function**: Use the top search box to find specific elements
- **Expand/Collapse**: Control tree structure expansion with top buttons
- **View Raw XML**: View unprocessed XML content
- **Reload**: Refresh the current analysis results
- **Recapture UI**: Provides a friendly dialog guiding users to run the script in the terminal to get new UI data, with a refresh button to view the latest results
- **Import Existing UI**: Allows separate import of XML files and screenshots for manual UI updates
  - Import XML File: Updates the UI structure tree without affecting the screenshot
  - Import Screenshot: Updates the interface screenshot without affecting the UI structure tree

## Directory Structure

```
.
├── auto_view_ui.sh    # Main script file
└── resources/         # Resource directory
    ├── no_image.png   # Placeholder image when screenshot capture fails
    └── Screenshot.png # Example interface screenshot
```

## Troubleshooting

1. **Device not found**:
   - Ensure the device is properly connected and USB debugging is authorized
   - Run `adb devices` to check if the device is recognized
   - Check if the USB cable is working properly

2. **Cannot retrieve UI structure**:
   - Some applications may restrict UI retrieval, try different applications
   - Ensure the device is not locked
   - Try restarting the ADB service: `adb kill-server && adb start-server`

3. **Chinese/Japanese character display issues**:
   - The script has built-in functionality to handle multi-language characters
   - If problems persist, check the language settings on your device and computer

4. **HTML viewer cannot open**:
   - Manually open the generated HTML file: `auto_view/[timestamp]/viewer.html`
   - Check if your browser supports modern JavaScript features

## Advanced Usage

### Custom ADB Path

If your ADB is not in the standard path, you can modify the environment variable settings at the beginning of the script:

```bash
export ANDROID_SDK_ROOT=/your/custom/path
```

### Integration with Other Tools

You can integrate this script into automated testing processes:

```bash
./auto_view_ui.sh && echo "UI analysis complete"
```

## Improvement Suggestions

### Update UI Data Directly in Current Interface

Implemented improvements:
1. ✅ Allow separate import of XML files and screenshots for manual UI updates
2. ✅ Add multi-language support (English/Chinese)

Future improvements may include:
1. Implement functionality to update UI data directly in the current HTML viewer without refreshing the page
2. Create a simple local server to handle UI capture requests
3. Add WebSocket support for real-time UI updates
4. Develop a browser extension to execute scripts directly from the browser

## License

This tool is for personal learning and development use only.

## Contribution

Bug reports and improvement suggestions are welcome. 