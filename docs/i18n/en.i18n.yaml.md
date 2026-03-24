# `i18n/en.i18n.yaml`

YAML under `lib/i18n/` defines translation strings or metadata for localization. Inline `#` comments in the YAML (if any) describe translator context; prefer editing the `.yaml` sources and regenerating Dart bindings with `dart run slang`.

## File role

- `_missing_translations.yaml` / `_unused_translations.yaml`: slang maintenance lists.
- `*.i18n.yaml`: locale string trees consumed by slang.

## Contents overview

```yaml
common:
  delete: Delete 
  done: Done
  continueBtn: Continue
  cancel: Cancel
home:
  folderColor:
    changeColor: Change color
    chooseColor: Choose color
    reset: Reset color
  sortNames:
    sort: Sort
    alphabetical: Alphabetical
    lastModified: Last modified
    sizeOnDisk: Size on disk
    increasing: Increasing
  selectAllNotes: Select all
  deselectAllNotes: Deselect all
  tabs:
    search: Search
    home: Home
    browse: Browse
    whiteboard: Whiteboard
    settings: Settings
  titles:
    search: Search
    home: Recent notes
    browse: Browse
    whiteboard: Whiteboard
    settings: Settings
  graph:
    showingNotes: Showing $shown of $total notes
    rootSearchHint: Search by name or tag to set root
    clearRoot: All notes
    selectRoot: Select root
  tooltips:
    viewMode: Toggle view mode
    treeView: Tree view
    folderView: Folder view
    newNote: New note
    showUpdateDialog: Show update dialog
    exportNote: Export note
  create: 
    newNote: New note
    importNote: Import note
    infiniteNote: Infinite note
  welcome: Welcome to Notes
  invalidFormat: The file you selected is not supported. Please select an sbn, sbn2, sba, or pdf file.
  noFiles: No files found
  noPreviewAvailable: No preview available
  createNewNote: Tap the + button to create a new note
  backFolder: Go back to the previous folder
  newFolder: 
    newFolder: New folder
    folderName: Folder name
    create: Create
    folderNameEmpty: Folder name can't be empty
    folderNameContainsSlash: Folder name can't contain a slash
    folderNameExists: Folder already exists
  renameNote: 
    renameNote: Rename note
    noteName: Note name
    rename: Rename
    noteNameEmpty: Note name can't be empty
    noteNameContainsSlash: Note name can't contain a slash
    noteNameExists: A note with this name already exists
  moveNote: 
    moveNote: Move note
    moveNotes: Move $n notes
    moveName: Move $f
    move: Move
    renamedTo: Note will be renamed to $newName
    multipleRenamedTo: "The following notes will be renamed:"
    numberRenamedTo: $n notes will be renamed to avoid conflicts
  deleteNote: Delete note
  renameFolder: 
    renameFolder: Rename folder
    folderName: Folder name
    rename: Rename
    folderNameEmpty: Folder name can't be empty
    folderNameContainsSlash: Folder name can't contain a slash
    folderNameExists: A folder with this name already exists
  deleteFolder:
    deleteFolder: Delete folder
    deleteName: Delete $f
    delete: Delete
    alsoDeleteContents: Also delete all notes inside this folder
  moveFolder:
    moveFolder: Move folder
    moveName: Move $f
    move: Move
    renamedTo: Folder will be renamed to $newName
    cantMoveHere: Cannot move folder here
  folderColorTitle: Folder Color
  noNotesFound: No notes found
  noSubfolders: No subfolders
  moveFolderTo: Move "$name" to...
  goUp: Go up
  root: Root
  properties: Properties
  path: Path
  pathValue: "Path: $path"
  lastModified: Last Modified
  lastModifiedValue: "Last Modified: $date"
  size: Size
  sizeValue: "Size: $size KB"
  close: Close
  deleteNoteConfirm: Are you sure you want to delete this note?
  color: Color
  noNotesToGraph: No notes to graph
  failedToLoadGraph: "Failed to load graph: $error"
  graphTitle: Graph
  importPdf: Import PDF
  pdfFilesSelected: "You selected $count PDF files. How would you like to import them?"
  separateNotes: Separate Notes
  mergeIntoOne: Merge into one file
  deviceNoPdfImport: This device does not support PDF import.
  errorImporting: "Error when importing: $error"
  filesImported: $count imported files
sentry: 
  consent: 
    title: Help improve Saber?
    description: 
      question: Would you like to automatically report unexpected errors? This helps me identify and fix issues faster.
      scope: The reports may contain information about the error and your device. I've made every effort to filter out personal data but some may remain.
      currentlyOff: If you grant consent, error reporting will be enabled after you restart the app.
      currentlyOn: If you revoke consent, please restart the app to disable error reporting.
      learnMoreInPrivacyPolicy(rich): Learn more in the ${link(privacy policy)}.
    answers: 
      yes: Yes
      no: No
      later: Ask me later
settings:
  prefLabels:
    strokeStabilization: Stroke stabilization
    flatEdge: Flat edge
    highlighterCapFlat: Flat
    highlighterCapRound: Round
    strokeStabilizationAmount: Stabilization amount
    strokePrediction: Stroke prediction
    strokePredictionAmount: Prediction strength
    toolbarColorSlotsCount: Toolbar color slots
    themeVariant: Theme variant
    locale: Language
    appTheme: App theme
    platform: Theme type
    layoutSize: Layout type
    customAccentColor: Custom accent color
    hyperlegibleFont: Atkinson Hyperlegible font
    shouldCheckForUpdates: Check for Saber updates
    shouldAlwaysAlertForUpdates: Faster updates
    allowInsecureConnections: Allow insecure connections
    editorToolbarAlignment: Toolbar position
    editorToolbarShowInFullscreen: Show the toolbar in fullscreen mode
    editorAutoInvert: Invert notes in dark mode
    preferGreyscale: Prefer greyscale colors
    maxImageSize: Maximum image size
    autoClearWhiteboardOnExit: Auto-clear the whiteboard
    disableEraserAfterUse: Auto-disable the eraser
    hideFingerDrawingToggle: Hide the finger drawing toggle
    autoDisableFingerDrawingWhenStylusDetected: Auto-disable finger drawing
    editorPromptRename: Prompt you to rename new notes
    recentColorsDontSavePresets: Don't save preset colors in recent colors
    recentColorsLength: How many recent colors to store
    printPageIndicators: Print page indicators
    autosave: Auto-save
    shapeRecognitionDelay: Shape recognition delay
    autoStraightenLines: Auto straighten lines
    simplifiedHomeLayout: Simplified home layout
    customDataDir: Custom Saber folder
    sentry: Error reporting
  prefDescriptions:
    strokeStabilization: Smooths out your handwriting
    strokePrediction: Draws a short ink tip slightly ahead of the stylus while you move (not saved in the note; reduces perceived lag)
    strokePredictionAmount: How far ahead to extrapolate while drawing
    toolbarColorSlotsCount: Number of colors to show in the toolbar
    themeVariant: Color scheme variant
    hyperlegibleFont: Increases legibility for users with low vision
    allowInsecureConnections: (Not recommended) Allow Saber to connect to servers with self-signed/untrusted certificates
    preferGreyscale: For e-ink displays
    autoClearWhiteboardOnExit: Clears the whiteboard after you exit the app
    disableEraserAfterUse: Automatically switches back to the pen after using the eraser
    maxImageSize: Larger images will be compressed
    hideFingerDrawing: 
      shown: Prevents accidental toggling
      fixedOn: Finger drawing is fixed as enabled
      fixedOff: Finger drawing is fixed as disabled
    autoDisableFingerDrawingWhenStylusDetected: Turn off finger drawing when a stylus is detected
    editorPromptRename: You can always rename notes later
    printPageIndicators: Show page indicators in exports
    autosave: Auto-save after a short delay, or never
    shapeRecognitionDelay: Hold at end of stroke for this long to recognize and replace with a clean shape (line, rectangle, circle, etc.). Set to Never to disable.
    autoStraightenLines: With highlighter, replace straight strokes with a clean line.
    simplifiedHomeLayout: Sets a fixed height for each note preview
    shouldAlwaysAlertForUpdates: Tell me about updates as soon as they're available
    sentry: 
      active: Active
      inactive: Inactive
      activeUntilRestart: Active until you restart the app
      inactiveUntilRestart: Inactive until you restart the app
  themeVariants:
    material: Material
    amoled: AMOLED 
  prefCategories: 
    security: Privacy & Security
    general: General
    writing: Writing
    editor: Editor
    performance: Performance
    advanced: Advanced
  themeModes: 
    system: System
    light: Light
    dark: Dark
  layoutSizes: 
    auto: Auto
    phone: Phone
    tablet: Tablet
  accentColorPicker: 
    pickAColor: Pick a color
  systemLanguage: Auto
  axisDirections: 
    - Top
    - Right
    - Bottom
    - Left
  reset: 
    title: Reset this setting?
    button: Reset
  resyncEverything: Resync everything
  openDataDir: Open Saber folder
  customDataDir: 
    cancel: Cancel
    select: Select
    mustBeEmpty: Selected folder must be empty
    mustBeDoneSyncing: Make sure syncing is complete before changing the folder
    unsupported: This feature is currently only for developers. Using it will likely result in data loss.
  autosaveDisabled: Never
  shapeRecognitionDisabled: Never
  defaultPageColor: Default Page Color
  pageColor: Page Color
  defaultLineColor: Default Line Color
  lineColor: Line Color
  defaultLineHeight: "Default Line Height: $height"
  defaultMargins: Default Margins
  defaultMarginColor: Default Margin Color
  invertInDarkMode: Invert in dark mode
  invertColors: Invert Colors
  invertColorsSubtitle: Ideal for dark mode
  selectTitle: Select $title
logs: 
  logs: Logs
  viewLogs: View logs
  debuggingInfo: Logs contain information useful for debugging and development
  noLogs: No logs here!
  useTheApp: Logs will appear here as you use the app
login: 
  title: Login
  form: 
    agreeToPrivacyPolicy(rich): By logging in, you agree to the ${linkToPrivacyPolicy(Privacy Policy)}.
  signup(rich): Don't have an account yet? ${linkToSignup(Sign up now)}!
  notYou(rich): Not you? ${undoLogin(Choose another account)}.
  status: 
    loggedOut: Logged out
    tapToLogin: Tap to log in with Nextcloud
    hi: Hi, $u!
    almostDone: Almost ready for syncing, tap to finish logging in
    loggedIn: Logged in with Nextcloud
  ncLoginStep: 
    whereToStoreData: "Choose where you want to store your data:"
    saberNcServer: Saber's Nextcloud server
    otherNcServer: Other Nextcloud server
    serverUrl: Server URL
    loginWithSaber: Login with Saber
    loginWithNextcloud: Login with Nextcloud
    loginFlow: 
      pleaseAuthorize: Please authorize Saber to access your Nextcloud account
      followPrompts: Please follow the prompts in the Nextcloud interface
      browserDidntOpen: Login page didn't open? Click here
  encLoginStep: 
    enterEncPassword: "To protect your data, please enter your encryption password:"
    newToSaber: New to Saber? Just enter a new encryption password.
    encPassword: Encryption password
    encFaqTitle: Frequently asked questions
    wrongEncPassword: Decryption failed with the provided password. Please try entering it again.
    connectionFailed: Something went wrong connecting to the server. Please try again later.
    encFaq: 
      - 
        q: What is an encryption password? Why use two passwords?
        a: |-
          The Nextcloud password is used to access the cloud. The encryption password "scrambles" your data before it ever reaches the cloud.
          Even if someone gains access to your Nextcloud account, your notes will remain safe and encrypted with a separate password. This provides you a second layer of security to protect your data.
          No-one can access your notes on the server without your encryption password, but this also means that if you forget your encryption password, you will lose access to your data.
      - 
        q: I haven't set an encryption password yet. Where do I get it?
        a: |-
          Choose a new encryption password and enter it above.
          Saber will generate your encryption keys from this password automatically.
      - 
        q: Can I use the same password as my Nextcloud account?
        a: Yes, but keep in mind that it would be easier for the server administrator or someone else to access your notes if they gain access to your Nextcloud account.
profile: 
  title: My profile
  logou

… (truncated in docs preview)

```
