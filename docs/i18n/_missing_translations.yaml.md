# `i18n/_missing_translations.yaml`

YAML under `lib/i18n/` defines translation strings or metadata for localization. Inline `#` comments in the YAML (if any) describe translator context; prefer editing the `.yaml` sources and regenerating Dart bindings with `dart run slang`.

## File role

- `_missing_translations.yaml` / `_unused_translations.yaml`: slang maintenance lists.
- `*.i18n.yaml`: locale string trees consumed by slang.

## Contents overview

```yaml
"@@info": 
  - Here are translations that exist in <en> but not in secondary locales.
  - After editing this file, you can run 'dart run slang apply --locale=<locale>' to quickly apply the newly added translations.
ar: 
  home: 
    noPreviewAvailable(OUTDATED): No preview available
  sentry: 
    consent: 
      title(OUTDATED): Help improve Saber?
      description: 
        question(OUTDATED): Would you like to automatically report unexpected errors? This helps me identify and fix issues faster.
        scope(OUTDATED): The reports may contain information about the error and your device. I've made every effort to filter out personal data but some may remain.
        currentlyOff(OUTDATED): If you grant consent, error reporting will be enabled after you restart the app.
        currentlyOn(OUTDATED): If you revoke consent, please restart the app to disable error reporting.
        learnMoreInPrivacyPolicy(rich)(OUTDATED): Learn more in the ${link(privacy policy)}.
      answers: 
        yes(OUTDATED): Yes
        no(OUTDATED): No
        later(OUTDATED): Ask me later
  settings: 
    prefLabels: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Auto-disable finger drawing
      autosave(OUTDATED): Auto-save
      sentry(OUTDATED): Error reporting
    prefDescriptions: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Turn off finger drawing when a stylus is detected
      autosave(OUTDATED): Auto-save after a short delay, or never
      sentry: 
        active(OUTDATED): Active
        inactive(OUTDATED): Inactive
        activeUntilRestart(OUTDATED): Active until you restart the app
        inactiveUntilRestart(OUTDATED): Inactive until you restart the app
    customDataDir: 
      unsupported(OUTDATED): This feature is currently only for developers. Using it will likely result in data loss.
    autosaveDisabled(OUTDATED): Never
    shapeRecognitionDisabled(OUTDATED): Never
  logs: 
    logs(OUTDATED): Logs
    viewLogs(OUTDATED): View logs
    debuggingInfo(OUTDATED): Logs contain information useful for debugging and development
    noLogs(OUTDATED): No logs here!
    useTheApp(OUTDATED): Logs will appear here as you use the app
  editor: 
    menu: 
      lineThickness(OUTDATED): Line thickness
      lineThicknessDescription(OUTDATED): Background line thickness
cs: 
de: 
eo: 
  settings: 
    prefLabels: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Auto-disable finger drawing
    prefDescriptions: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Turn off finger drawing when a stylus is detected
es: 
  common: 
    done(OUTDATED): Done
    continueBtn(OUTDATED): Continue
  home: 
    noPreviewAvailable(OUTDATED): No preview available
  sentry: 
    consent: 
      title(OUTDATED): Help improve Saber?
      description: 
        question(OUTDATED): Would you like to automatically report unexpected errors? This helps me identify and fix issues faster.
        scope(OUTDATED): The reports may contain information about the error and your device. I've made every effort to filter out personal data but some may remain.
        currentlyOff(OUTDATED): If you grant consent, error reporting will be enabled after you restart the app.
        currentlyOn(OUTDATED): If you revoke consent, please restart the app to disable error reporting.
        learnMoreInPrivacyPolicy(rich)(OUTDATED): Learn more in the ${link(privacy policy)}.
      answers: 
        yes(OUTDATED): Yes
        no: No
        later(OUTDATED): Ask me later
  settings: 
    prefCategories: 
      performance(OUTDATED): Performance
    prefLabels: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Auto-disable finger drawing
      autosave(OUTDATED): Auto-save
      shapeRecognitionDelay(OUTDATED): Shape recognition delay
      autoStraightenLines(OUTDATED): Auto straighten lines
      simplifiedHomeLayout(OUTDATED): Simplified home layout
      customDataDir(OUTDATED): Custom Saber folder
      sentry(OUTDATED): Error reporting
    prefDescriptions: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Turn off finger drawing when a stylus is detected
      autosave(OUTDATED): Auto-save after a short delay, or never
      shapeRecognitionDelay(OUTDATED): How often to update the shape preview
      autoStraightenLines(OUTDATED): Straightens long lines without having to use the shape pen
      simplifiedHomeLayout(OUTDATED): Sets a fixed height for each note preview
      sentry: 
        active(OUTDATED): Active
        inactive(OUTDATED): Inactive
        activeUntilRestart(OUTDATED): Active until you restart the app
        inactiveUntilRestart(OUTDATED): Inactive until you restart the app
    resyncEverything(OUTDATED): Resync everything
    openDataDir(OUTDATED): Open Saber folder
    customDataDir: 
      cancel(OUTDATED): Cancel
      select(OUTDATED): Select
      mustBeEmpty(OUTDATED): Selected folder must be empty
      mustBeDoneSyncing(OUTDATED): Make sure syncing is complete before changing the folder
      unsupported(OUTDATED): This feature is currently only for developers. Using it will likely result in data loss.
    autosaveDisabled(OUTDATED): Never
    shapeRecognitionDisabled(OUTDATED): Never
  logs: 
    logs(OUTDATED): Logs
    viewLogs(OUTDATED): View logs
    debuggingInfo(OUTDATED): Logs contain information useful for debugging and development
    noLogs(OUTDATED): No logs here!
    useTheApp(OUTDATED): Logs will appear here as you use the app
  login: 
    notYou(rich)(OUTDATED): Not you? ${undoLogin(Choose another account)}.
    status: 
      hi(OUTDATED): Hi, $u!
      almostDone(OUTDATED): Almost ready for syncing, tap to finish logging in
    ncLoginStep: 
      whereToStoreData(OUTDATED): "Choose where you want to store your data:"
      saberNcServer(OUTDATED): Saber's Nextcloud server
      otherNcServer(OUTDATED): Other Nextcloud server
      serverUrl(OUTDATED): Server URL
      loginWithSaber(OUTDATED): Login with Saber
      loginWithNextcloud(OUTDATED): Login with Nextcloud
      loginFlow: 
        pleaseAuthorize(OUTDATED): Please authorize Saber to access your Nextcloud account
        followPrompts(OUTDATED): Please follow the prompts in the Nextcloud interface
        browserDidntOpen(OUTDATED): Login page didn't open? Click here
    encLoginStep: 
      enterEncPassword(OUTDATED): "To protect your data, please enter your encryption password:"
      newToSaber(OUTDATED): New to Saber? Just enter a new encryption password.
      encPassword(OUTDATED): Encryption password
      encFaqTitle(OUTDATED): Frequently asked questions
      wrongEncPassword(OUTDATED): Decryption failed with the provided password. Please try entering it again.
      connectionFailed(OUTDATED): Something went wrong connecting to the server. Please try again later.
      encFaq(OUTDATED): 
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
    quotaUsage(OUTDATED): You're using $used of $total ($percent%)
    connectedTo(OUTDATED): Connected to
    faqTitle(OUTDATED): Frequently asked questions
  update: 
    downloadNotAvailableYet(OUTDATED): The download isn't available yet for your platform. Please check back shortly.
  editor: 
    pens: 
      fountainPen(OUTDATED): Fountain pen
      pencil(OUTDATED): Pencil
    colors: 
      customBrightnessHue(OUTDATED): Custom $b $h
    menu: 
      lineHeightDescription(OUTDATED): Also controls the text size for typed notes
      lineThickness(OUTDATED): Line thickness
      lineThicknessDescription(OUTDATED): Background line thickness
      watchServer(OUTDATED): Watch for updates on the server
      watchServerReadOnly(OUTDATED): Editing is disabled while watching the server
fa: 
  common: 
    done(OUTDATED): Done
    continueBtn(OUTDATED): Continue
  home: 
    noPreviewAvailable(OUTDATED): No preview available
  sentry: 
    consent: 
      title(OUTDATED): Help improve Saber?
      description: 
        question(OUTDATED): Would you like to automatically report unexpected errors? This helps me identify and fix issues faster.
        scope(OUTDATED): The reports may contain information about the error and your device. I've made every effort to filter out personal data but some may remain.
        currentlyOff(OUTDATED): If you grant consent, error reporting will be enabled after you restart the app.
        currentlyOn(OUTDATED): If you revoke consent, please restart the app to disable error reporting.
      answers: 
        yes(OUTDATED): Yes
        no(OUTDATED): No
        later(OUTDATED): Ask me later
  settings: 
    prefLabels: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Auto-disable finger drawing
      autosave(OUTDATED): Auto-save
      autoStraightenLines(OUTDATED): Auto straighten lines
      simplifiedHomeLayout(OUTDATED): Simplified home layout
      customDataDir(OUTDATED): Custom Saber folder
      sentry(OUTDATED): Error reporting
    prefDescriptions: 
      autoDisableFingerDrawingWhenStylusDetected(OUTDATED): Turn off finger drawing when a stylus is detected
      autosave(OUTDATED): Auto-save after a short delay, or never
      autoStraightenLines(OUTDATED): Straightens long lines without having to use the shape pen
      simplifiedHomeLayout(OUTDATED): Sets a fixed height for each note preview
      sentry: 
        active(OUTDATED): Active
        inactive(OUTDATED): Inactive
        activeUntilRestart(OUTDATED): Active until you restart the app
        inactiveUntilRestart(OUTDATED): Inactive until you restart the app
    resyncEverything(OUTDATED): Resync everything
    openDataDir(OUTDATED): Open Saber folder
    customDataDir: 
      cancel(OUTDATED): Cancel
      select(OUTDATED): Select
      mustBeEmpty(OUTDATED): Selected folder must be empty
      mustBeDoneSyncing(OUTDATED): Make sure syncing is complete before changing the folder
      unsupported(OUTDATED): This feature is currently only for developers. Using it will likely result in data loss.
    autosaveDisabled(OUTDATED): Never
    shapeRecognitionDisabled(OUTDATED): Never
  logs: 
    logs(OUTDATED): Logs
    viewLogs(OUTDATED): View logs
    debuggingInfo(OUTDATED): Logs contain information useful for debugging and development
    noLogs(OUTDATED): No logs here!
    useTheApp(OUTDATED): Logs will appear here as you use the app
  login: 
    notYou(rich)(OUTDATED): Not you? ${undoLogin(Choose another account)}.
    status: 
      hi(OUTDATED): Hi, $u!
      almostDone(OUTDATED): Almost ready for syncing, tap to finish logging in
    ncLoginStep: 
      whereToStoreData(OUTDATED): "Choose where you want to store your data:"
      saberNcServer(OUTDATED): Saber's Nextcloud server
      otherNcServer(OUTDATED): Other Nextcloud server
      serverUrl(OUTDATED): Server URL
      loginWithSaber(OUTDATED): Login with Saber
      loginWithNextcloud(OUTDATED): Login with Nextcloud
      loginFlow: 
        pleaseAu

… (truncated in docs preview)

```
