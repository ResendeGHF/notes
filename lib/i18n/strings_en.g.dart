///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

part of 'strings.g.dart';

// Path: <root>
typedef TranslationsEn = Translations; // ignore: unused_element
class Translations with BaseTranslations<AppLocale, Translations> {
	/// Returns the current translations of the given [context].
	///
	/// Usage:
	/// final t = Translations.of(context);
	static Translations of(BuildContext context) => InheritedLocaleData.of<AppLocale, Translations>(context).translations;

	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	Translations({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.en,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  );

	/// Metadata for the translations of <en>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	late final Translations _root = this; // ignore: unused_field

	Translations $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => Translations(meta: meta ?? this.$meta);

	// Translations
	late final Translations$common$en common = Translations$common$en.internal(_root);
	late final Translations$home$en home = Translations$home$en.internal(_root);
	late final Translations$sentry$en sentry = Translations$sentry$en.internal(_root);
	late final Translations$settings$en settings = Translations$settings$en.internal(_root);
	late final Translations$logs$en logs = Translations$logs$en.internal(_root);
	late final Translations$login$en login = Translations$login$en.internal(_root);
	late final Translations$profile$en profile = Translations$profile$en.internal(_root);
	late final Translations$appInfo$en appInfo = Translations$appInfo$en.internal(_root);
	late final Translations$update$en update = Translations$update$en.internal(_root);
	late final Translations$editor$en editor = Translations$editor$en.internal(_root);
	late final Translations$export$en export = Translations$export$en.internal(_root);
	late final Translations$vault$en vault = Translations$vault$en.internal(_root);
	late final Translations$toolbar$en toolbar = Translations$toolbar$en.internal(_root);
	late final Translations$backup$en backup = Translations$backup$en.internal(_root);
}

// Path: common
class Translations$common$en {
	Translations$common$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Done'
	String get done => 'Done';

	/// en: 'Continue'
	String get continueBtn => 'Continue';

	/// en: 'Cancel'
	String get cancel => 'Cancel';
}

// Path: home
class Translations$home$en {
	Translations$home$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$home$folderColor$en folderColor = Translations$home$folderColor$en.internal(_root);
	late final Translations$home$sortNames$en sortNames = Translations$home$sortNames$en.internal(_root);

	/// en: 'Select all'
	String get selectAllNotes => 'Select all';

	/// en: 'Deselect all'
	String get deselectAllNotes => 'Deselect all';

	late final Translations$home$tabs$en tabs = Translations$home$tabs$en.internal(_root);
	late final Translations$home$titles$en titles = Translations$home$titles$en.internal(_root);
	late final Translations$home$graph$en graph = Translations$home$graph$en.internal(_root);
	late final Translations$home$tooltips$en tooltips = Translations$home$tooltips$en.internal(_root);
	late final Translations$home$create$en create = Translations$home$create$en.internal(_root);

	/// en: 'Welcome to Notes'
	String get welcome => 'Welcome to Notes';

	/// en: 'The file you selected is not supported. Please select an sbn, sbn2, sba, or pdf file.'
	String get invalidFormat => 'The file you selected is not supported. Please select an sbn, sbn2, sba, or pdf file.';

	/// en: 'No files found'
	String get noFiles => 'No files found';

	/// en: 'No preview available'
	String get noPreviewAvailable => 'No preview available';

	late final Translations$home$fileList$en fileList = Translations$home$fileList$en.internal(_root);

	/// en: 'Tap the + button to create a new note'
	String get createNewNote => 'Tap the + button to create a new note';

	/// en: 'Go back to the previous folder'
	String get backFolder => 'Go back to the previous folder';

	late final Translations$home$newFolder$en newFolder = Translations$home$newFolder$en.internal(_root);
	late final Translations$home$renameNote$en renameNote = Translations$home$renameNote$en.internal(_root);
	late final Translations$home$moveNote$en moveNote = Translations$home$moveNote$en.internal(_root);

	/// en: 'Delete note'
	String get deleteNote => 'Delete note';

	late final Translations$home$renameFolder$en renameFolder = Translations$home$renameFolder$en.internal(_root);
	late final Translations$home$deleteFolder$en deleteFolder = Translations$home$deleteFolder$en.internal(_root);
	late final Translations$home$moveFolder$en moveFolder = Translations$home$moveFolder$en.internal(_root);

	/// en: 'Folder Color'
	String get folderColorTitle => 'Folder Color';

	/// en: 'No notes found'
	String get noNotesFound => 'No notes found';

	/// en: 'No subfolders'
	String get noSubfolders => 'No subfolders';

	/// en: 'Move "$name" to...'
	String moveFolderTo({required Object name}) => 'Move "${name}" to...';

	/// en: 'Go up'
	String get goUp => 'Go up';

	/// en: 'Root'
	String get root => 'Root';

	/// en: 'Properties'
	String get properties => 'Properties';

	/// en: 'Path'
	String get path => 'Path';

	/// en: 'Path: $path'
	String pathValue({required Object path}) => 'Path: ${path}';

	/// en: 'Last Modified'
	String get lastModified => 'Last Modified';

	/// en: 'Last Modified: $date'
	String lastModifiedValue({required Object date}) => 'Last Modified: ${date}';

	/// en: 'Size'
	String get size => 'Size';

	/// en: 'Size: $size KB'
	String sizeValue({required Object size}) => 'Size: ${size} KB';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Are you sure you want to delete this note?'
	String get deleteNoteConfirm => 'Are you sure you want to delete this note?';

	/// en: 'Color'
	String get color => 'Color';

	/// en: 'No notes to graph'
	String get noNotesToGraph => 'No notes to graph';

	/// en: 'Failed to load graph: $error'
	String failedToLoadGraph({required Object error}) => 'Failed to load graph: ${error}';

	/// en: 'Graph'
	String get graphTitle => 'Graph';

	/// en: 'Import PDF'
	String get importPdf => 'Import PDF';

	/// en: 'You selected $count PDF files. How would you like to import them?'
	String pdfFilesSelected({required Object count}) => 'You selected ${count} PDF files. How would you like to import them?';

	/// en: 'Separate Notes'
	String get separateNotes => 'Separate Notes';

	/// en: 'Merge into one file'
	String get mergeIntoOne => 'Merge into one file';

	/// en: 'This device does not support PDF import.'
	String get deviceNoPdfImport => 'This device does not support PDF import.';

	/// en: 'Error when importing: $error'
	String errorImporting({required Object error}) => 'Error when importing: ${error}';

	/// en: '$count imported files'
	String filesImported({required Object count}) => '${count} imported files';
}

// Path: sentry
class Translations$sentry$en {
	Translations$sentry$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$sentry$consent$en consent = Translations$sentry$consent$en.internal(_root);
}

// Path: settings
class Translations$settings$en {
	Translations$settings$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$settings$prefLabels$en prefLabels = Translations$settings$prefLabels$en.internal(_root);
	late final Translations$settings$prefDescriptions$en prefDescriptions = Translations$settings$prefDescriptions$en.internal(_root);
	late final Translations$settings$themeVariants$en themeVariants = Translations$settings$themeVariants$en.internal(_root);
	late final Translations$settings$prefCategories$en prefCategories = Translations$settings$prefCategories$en.internal(_root);
	late final Translations$settings$noteInkDefaults$en noteInkDefaults = Translations$settings$noteInkDefaults$en.internal(_root);
	late final Translations$settings$themeModes$en themeModes = Translations$settings$themeModes$en.internal(_root);
	late final Translations$settings$layoutSizes$en layoutSizes = Translations$settings$layoutSizes$en.internal(_root);
	late final Translations$settings$accentColorPicker$en accentColorPicker = Translations$settings$accentColorPicker$en.internal(_root);

	/// en: 'Auto'
	String get systemLanguage => 'Auto';

	List<String> get axisDirections => [
		'Top',
		'Right',
		'Bottom',
		'Left',
	];
	late final Translations$settings$reset$en reset = Translations$settings$reset$en.internal(_root);

	/// en: 'Resync everything'
	String get resyncEverything => 'Resync everything';

	/// en: 'Open Saber folder'
	String get openDataDir => 'Open Saber folder';

	late final Translations$settings$customDataDir$en customDataDir = Translations$settings$customDataDir$en.internal(_root);

	/// en: 'Never'
	String get autosaveDisabled => 'Never';

	/// en: 'Never'
	String get shapeRecognitionDisabled => 'Never';

	/// en: 'Default Page Color'
	String get defaultPageColor => 'Default Page Color';

	/// en: 'Page Color'
	String get pageColor => 'Page Color';

	/// en: 'Default Line Color'
	String get defaultLineColor => 'Default Line Color';

	/// en: 'Line Color'
	String get lineColor => 'Line Color';

	/// en: 'Default Line Height: $height'
	String defaultLineHeight({required Object height}) => 'Default Line Height: ${height}';

	/// en: 'Default Margins'
	String get defaultMargins => 'Default Margins';

	/// en: 'Default Margin Color'
	String get defaultMarginColor => 'Default Margin Color';

	/// en: 'Invert in dark mode'
	String get invertInDarkMode => 'Invert in dark mode';

	/// en: 'Invert Colors'
	String get invertColors => 'Invert Colors';

	/// en: 'Ideal for dark mode'
	String get invertColorsSubtitle => 'Ideal for dark mode';

	/// en: 'Select $title'
	String selectTitle({required Object title}) => 'Select ${title}';
}

// Path: logs
class Translations$logs$en {
	Translations$logs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Logs'
	String get logs => 'Logs';

	/// en: 'View logs'
	String get viewLogs => 'View logs';

	/// en: 'Logs contain information useful for debugging and development'
	String get debuggingInfo => 'Logs contain information useful for debugging and development';

	/// en: 'No logs here!'
	String get noLogs => 'No logs here!';

	/// en: 'Logs will appear here as you use the app'
	String get useTheApp => 'Logs will appear here as you use the app';
}

// Path: login
class Translations$login$en {
	Translations$login$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Login'
	String get title => 'Login';

	late final Translations$login$form$en form = Translations$login$form$en.internal(_root);

	/// en: 'Don't have an account yet? ${linkToSignup(Sign up now)}!'
	TextSpan signup({required InlineSpanBuilder linkToSignup}) => TextSpan(children: [
		const TextSpan(text: 'Don\'t have an account yet? '),
		linkToSignup('Sign up now'),
		const TextSpan(text: '!'),
	]);

	/// en: 'Not you? ${undoLogin(Choose another account)}.'
	TextSpan notYou({required InlineSpanBuilder undoLogin}) => TextSpan(children: [
		const TextSpan(text: 'Not you? '),
		undoLogin('Choose another account'),
		const TextSpan(text: '.'),
	]);

	late final Translations$login$status$en status = Translations$login$status$en.internal(_root);
	late final Translations$login$ncLoginStep$en ncLoginStep = Translations$login$ncLoginStep$en.internal(_root);
	late final Translations$login$encLoginStep$en encLoginStep = Translations$login$encLoginStep$en.internal(_root);
}

// Path: profile
class Translations$profile$en {
	Translations$profile$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'My profile'
	String get title => 'My profile';

	/// en: 'Log out'
	String get logout => 'Log out';

	/// en: 'You're using $used of $total ($percent%)'
	String quotaUsage({required Object used, required Object total, required Object percent}) => 'You\'re using ${used} of ${total} (${percent}%)';

	/// en: 'Connected to'
	String get connectedTo => 'Connected to';

	late final Translations$profile$quickLinks$en quickLinks = Translations$profile$quickLinks$en.internal(_root);

	/// en: 'Frequently asked questions'
	String get faqTitle => 'Frequently asked questions';

	List<dynamic> get faq => [
		Translations$profile$faq$0$en.internal(_root),
		Translations$profile$faq$1$en.internal(_root),
		Translations$profile$faq$2$en.internal(_root),
		Translations$profile$faq$3$en.internal(_root),
	];
}

// Path: appInfo
class Translations$appInfo$en {
	Translations$appInfo$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Notes Copyright © 2025-$buildYear Gustavo Resende Saber Copyright © 2022-$buildYear Adil Hanney This program comes with absolutely no warranty. This is free software, and you are welcome to redistribute it under certain conditions.'
	String licenseNotice({required Object buildYear}) => 'Notes  Copyright © 2025-${buildYear}  Gustavo Resende\nSaber  Copyright © 2022-${buildYear}  Adil Hanney\nThis program comes with absolutely no warranty. This is free software, and you are welcome to redistribute it under certain conditions.';

	/// en: 'DEBUG'
	String get debug => 'DEBUG';

	/// en: 'Tap here to sponsor me or buy more storage'
	String get sponsorButton => 'Tap here to sponsor me or buy more storage';

	/// en: 'Tap here to view more license information'
	String get licenseButton => 'Tap here to view more license information';

	/// en: 'Tap here to view the privacy policy'
	String get privacyPolicyButton => 'Tap here to view the privacy policy';
}

// Path: update
class Translations$update$en {
	Translations$update$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Update available'
	String get updateAvailable => 'Update available';

	/// en: 'A new version of the app is available:'
	String get updateAvailableDescription => 'A new version of the app is available:';

	/// en: 'Update'
	String get update => 'Update';

	/// en: 'The download isn't available yet for your platform. Please check back shortly.'
	String get downloadNotAvailableYet => 'The download isn\'t available yet for your platform. Please check back shortly.';
}

// Path: editor
class Translations$editor$en {
	Translations$editor$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations
	late final Translations$editor$navigation$en navigation = Translations$editor$navigation$en.internal(_root);
	late final Translations$editor$pens$en pens = Translations$editor$pens$en.internal(_root);
	late final Translations$editor$selectionBar$en selectionBar = Translations$editor$selectionBar$en.internal(_root);
	late final Translations$editor$toolbar$en toolbar = Translations$editor$toolbar$en.internal(_root);
	late final Translations$editor$penOptions$en penOptions = Translations$editor$penOptions$en.internal(_root);
	late final Translations$editor$penSizePresets$en penSizePresets = Translations$editor$penSizePresets$en.internal(_root);
	late final Translations$editor$colors$en colors = Translations$editor$colors$en.internal(_root);
	late final Translations$editor$pdfLoading$en pdfLoading = Translations$editor$pdfLoading$en.internal(_root);
	late final Translations$editor$vaultPdfLargeRam$en vaultPdfLargeRam = Translations$editor$vaultPdfLargeRam$en.internal(_root);
	late final Translations$editor$imageOptions$en imageOptions = Translations$editor$imageOptions$en.internal(_root);
	late final Translations$editor$menu$en menu = Translations$editor$menu$en.internal(_root);
	late final Translations$editor$newerFileFormat$en newerFileFormat = Translations$editor$newerFileFormat$en.internal(_root);
	late final Translations$editor$quill$en quill = Translations$editor$quill$en.internal(_root);
	late final Translations$editor$hud$en hud = Translations$editor$hud$en.internal(_root);

	/// en: 'Pages'
	String get pages => 'Pages';

	/// en: 'Untitled'
	String get untitled => 'Untitled';

	/// en: 'Saving your changes... You can safely exit the editor when it's done'
	String get needsToSaveBeforeExiting => 'Saving your changes... You can safely exit the editor when it\'s done';

	/// en: 'Plot 3D Surface'
	String get plot3dSurface => 'Plot 3D Surface';

	/// en: 'Add internal link'
	String get addInternalLink => 'Add internal link';

	/// en: 'No notes match this query'
	String get noNotesMatchQuery => 'No notes match this query';

	/// en: 'Tags & Links'
	String get tagsAndLinks => 'Tags & Links';

	/// en: 'No links on this page'
	String get noLinksOnPage => 'No links on this page';

	/// en: 'Stroke to Text'
	String get strokeToText => 'Stroke to Text';

	/// en: 'Selection to LaTeX'
	String get selectionToLatex => 'Selection to LaTeX';

	/// en: 'Note handwriting to LaTeX'
	String get noteHandwritingToLatex => 'Note handwriting to LaTeX';

	/// en: 'Recognized LaTeX'
	String get recognizedLatexTitle => 'Recognized LaTeX';

	/// en: 'Calculate'
	String get calculate => 'Calculate';

	/// en: 'Lock Image'
	String get lockImage => 'Lock Image';

	/// en: 'Unlock Image'
	String get unlockImage => 'Unlock Image';

	/// en: 'Crop image'
	String get cropImage => 'Crop image';

	/// en: 'Set as background'
	String get setAsBackground => 'Set as background';

	/// en: 'Copied to clipboard'
	String get copyToClipboard => 'Copied to clipboard';

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Go Back'
	String get goBack => 'Go Back';

	/// en: 'Add'
	String get add => 'Add';

	/// en: 'Close'
	String get close => 'Close';

	/// en: 'Image set as background'
	String get imageSetAsBackground => 'Image set as background';

	/// en: 'Crop is currently available only for bitmap images'
	String get cropBitmapOnly => 'Crop is currently available only for bitmap images';

	/// en: 'Failed to load image for cropping'
	String get failedToLoadImageForCrop => 'Failed to load image for cropping';

	/// en: 'Failed to resolve equation: $error'
	String failedToResolveEquation({required Object error}) => 'Failed to resolve equation: ${error}';

	/// en: 'Could not resolve the equation. Make sure to include the equals sign "=".'
	String get equationHint => 'Could not resolve the equation. Make sure to include the equals sign "=".';

	/// en: 'Could not recognize the text'
	String get couldNotRecognizeText => 'Could not recognize the text';

	/// en: 'Recognition error: $error'
	String recognitionError({required Object error}) => 'Recognition error: ${error}';

	/// en: 'Failed to delete note: $error'
	String failedToDeleteNote({required Object error}) => 'Failed to delete note: ${error}';

	/// en: 'Error importing image'
	String get errorImportingImage => 'Error importing image';

	/// en: 'Error importing image $index: $error'
	String errorImportingImageIndex({required Object index, required Object error}) => 'Error importing image ${index}: ${error}';

	/// en: 'Error inserting image: $error'
	String errorInsertingImage({required Object error}) => 'Error inserting image: ${error}';

	/// en: 'Create table'
	String get createTable => 'Create table';

	/// en: 'Data & Tools'
	String get dataAndTools => 'Data & Tools';

	/// en: 'Insert'
	String get insert => 'Insert';

	/// en: 'Export'
	String get export => 'Export';

	/// en: 'Split View'
	String get splitView => 'Split View';

	/// en: 'Actions'
	String get actions => 'Actions';

	/// en: 'Invert in dark mode'
	String get invertInDarkMode => 'Invert in dark mode';

	/// en: 'Override app setting just for this note'
	String get overrideAppSettingForNote => 'Override app setting just for this note';

	/// en: 'Replace default'
	String get replaceDefault => 'Replace default';

	/// en: 'Portrait'
	String get portrait => 'Portrait';

	/// en: 'Landscape'
	String get landscape => 'Landscape';

	/// en: 'Select $title'
	String selectTitle({required Object title}) => 'Select ${title}';

	/// en: 'Plot Function'
	String get plotFunction => 'Plot Function';

	/// en: 'Calculator'
	String get calculator => 'Calculator';

	/// en: 'Insert Table'
	String get insertTable => 'Insert Table';

	/// en: 'Plot 3D'
	String get plot3D => 'Plot 3D';

	/// en: 'Open Second Note'
	String get openSecondNote => 'Open Second Note';

	/// en: 'No notes match this search'
	String get noNotesMatchSearch => 'No notes match this search';

	/// en: 'Pick File'
	String get pickFile => 'Pick File';

	/// en: 'Editor'
	String get editorTitle => 'Editor';
}

// Path: export
class Translations$export$en {
	Translations$export$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'No valid pages selected'
	String get noValidPagesSelected => 'No valid pages selected';

	/// en: 'Export failed: $error'
	String exportFailed({required Object error}) => 'Export failed: ${error}';

	/// en: 'Export Note'
	String get exportNote => 'Export Note';

	/// en: 'Format'
	String get format => 'Format';

	/// en: 'PDF'
	String get pdf => 'PDF';

	/// en: 'PNG'
	String get png => 'PNG';

	/// en: 'Fast export; native encoding (best for high resolution)'
	String get pngSubtitle => 'Fast export; native encoding (best for high resolution)';

	/// en: 'JPEG'
	String get jpeg => 'JPEG';

	/// en: 'Smaller files; slower at high resolution than PNG'
	String get jpegSubtitle => 'Smaller files; slower at high resolution than PNG';

	/// en: 'Pages'
	String get pages => 'Pages';

	/// en: 'All Pages'
	String get allPages => 'All Pages';

	/// en: 'Current Page'
	String get currentPage => 'Current Page';

	/// en: 'Custom Range'
	String get customRange => 'Custom Range';

	/// en: 'Invert colors'
	String get invertColors => 'Invert colors';

	/// en: 'Export note with inverted page and ink colors'
	String get invertColorsSubtitle => 'Export note with inverted page and ink colors';

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Export'
	String get export => 'Export';

	/// en: 'Export SBA'
	String get exportSba => 'Export SBA';

	/// en: 'Export metadata'
	String get exportMetadata => 'Export metadata';

	/// en: 'Include creation and edit dates, time spent, location, and page fingerprint in the archive. Turn off for a cleaner share.'
	String get exportMetadataSubtitle => 'Include creation and edit dates, time spent, location, and page fingerprint in the archive. Turn off for a cleaner share.';

	/// en: 'Unencrypted'
	String get unencrypted => 'Unencrypted';

	/// en: 'Encrypted (set password)'
	String get encrypted => 'Encrypted (set password)';

	/// en: 'Set shared password'
	String get setSharedPassword => 'Set shared password';

	/// en: 'Encrypted SBA'
	String get encryptedSba => 'Encrypted SBA';

	/// en: 'Import'
	String get import => 'Import';

	/// en: 'Export unencrypted (share as-is) or encrypted with a password that you can share with the recipient. Links and tags are always removed when exporting.'
	String get exportSbaContent => 'Export unencrypted (share as-is) or encrypted with a password that you can share with the recipient.\n\nLinks and tags are always removed when exporting.';

	/// en: 'Enter a password to encrypt the SBA. Share this password with the recipient so they can open the file.'
	String get setPasswordContent => 'Enter a password to encrypt the SBA. Share this password with the recipient so they can open the file.';

	/// en: 'Password is required'
	String get passwordRequired => 'Password is required';

	/// en: 'Passwords do not match'
	String get passwordsDoNotMatch => 'Passwords do not match';

	/// en: 'Confirm password'
	String get confirmPassword => 'Confirm password';

	/// en: 'This SBA file is encrypted. Enter the shared password to import the note.'
	String get encryptedSbaContent => 'This SBA file is encrypted. Enter the shared password to import the note.';

	/// en: 'e.g. 1,3,5-7'
	String get customRangeHint => 'e.g. 1,3,5-7';

	/// en: 'Page numbers'
	String get pageNumbers => 'Page numbers';

	/// en: 'Resolution'
	String get resolution => 'Resolution';

	/// en: 'Vector strokes (lightweight, sharp at any zoom)'
	String get resolutionPdfVector => 'Vector strokes (lightweight, sharp at any zoom)';

	/// en: '72 DPI (fast)'
	String get resolution72 => '72 DPI (fast)';

	/// en: '150 DPI'
	String get resolution150 => '150 DPI';

	/// en: '300 DPI (print quality)'
	String get resolution300 => '300 DPI (print quality)';

	/// en: 'Export folder'
	String get exportFolder => 'Export folder';

	/// en: 'As SBA archives'
	String get exportFolderAsSba => 'As SBA archives';

	/// en: 'As PDF archives'
	String get exportFolderAsPdf => 'As PDF archives';

	/// en: 'One file per note — no split sbn2 assets'
	String get exportFolderSubtitle => 'One file per note — no split sbn2 assets';

	/// en: 'Preparing export...'
	String get preparingExport => 'Preparing export...';

	/// en: 'No notes to export in this folder'
	String get exportFolderEmpty => 'No notes to export in this folder';

	/// en: 'Share Links'
	String get shareLinks => 'Share Links';

	/// en: 'Embed linked pages in the export so the recipient gets a self-contained document'
	String get shareLinksSubtitle => 'Embed linked pages in the export so the recipient gets a self-contained document';

	/// en: 'Default export path'
	String get defaultExportPath => 'Default export path';

	/// en: 'Exported files are saved here. Required when exporting with Share Links.'
	String get defaultExportPathSubtitle => 'Exported files are saved here. Required when exporting with Share Links.';

	/// en: 'Please set Default export path in Settings before exporting with Share Links.'
	String get defaultExportPathRequired => 'Please set Default export path in Settings before exporting with Share Links.';

	/// en: 'Exporting note...'
	String get exportingNote => 'Exporting note...';

	/// en: 'Export complete'
	String get exportComplete => 'Export complete';

	/// en: 'Please import after export is finished.'
	String get importAfterExportDone => 'Please import after export is finished.';
}

// Path: vault
class Translations$vault$en {
	Translations$vault$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unlock'
	String get unlock => 'Unlock';

	/// en: 'Vault Locked'
	String get vaultLocked => 'Vault Locked';

	/// en: 'Please enter your password.'
	String get vaultLockedMessage => 'Please enter your password.';

	/// en: 'You have $count file(s) waiting to import. Unlock to continue.'
	String filesWaitingToImport({required Object count}) => 'You have ${count} file(s) waiting to import. Unlock to continue.';

	/// en: 'Password'
	String get password => 'Password';

	/// en: 'Failed to initialize vault. Please try again.'
	String get failedToInit => 'Failed to initialize vault. Please try again.';

	/// en: 'Incorrect password or corrupted vault.'
	String get incorrectOrCorrupted => 'Incorrect password or corrupted vault.';

	/// en: 'Failed to migrate files: $error Your files remain in their original location.'
	String migrationErrorContent({required Object error}) => 'Failed to migrate files: ${error}\n\nYour files remain in their original location.';

	/// en: 'Your notes have been encrypted and stored in the vault. You will need to enter your password when you restart the app.'
	String get vaultCreatedContent => 'Your notes have been encrypted and stored in the vault. You will need to enter your password when you restart the app.';

	/// en: 'Your notes have been decrypted and moved back to regular storage.'
	String get vaultDisabledContent => 'Your notes have been decrypted and moved back to regular storage.';

	/// en: 'Migration Error'
	String get migrationError => 'Migration Error';

	/// en: 'Vault Created'
	String get vaultCreated => 'Vault Created';

	/// en: 'Incorrect Password'
	String get incorrectPassword => 'Incorrect Password';

	/// en: 'The password you entered is incorrect.'
	String get incorrectPasswordMessage => 'The password you entered is incorrect.';

	/// en: 'Vault Disabled'
	String get vaultDisabled => 'Vault Disabled';

	/// en: 'Create Vault'
	String get createVault => 'Create Vault';

	/// en: 'Encryption Password'
	String get encryptionPassword => 'Encryption Password';

	/// en: 'Backup File Name'
	String get backupFileName => 'Backup File Name';

	/// en: 'Backup Complete'
	String get backupComplete => 'Backup Complete';

	/// en: 'Restore Complete'
	String get restoreComplete => 'Restore Complete';

	/// en: 'Error'
	String get error => 'Error';

	/// en: 'Migrating Files'
	String get migratingFiles => 'Migrating Files';

	/// en: 'Please wait while files are being migrated...'
	String get migratingFilesMessage => 'Please wait while files are being migrated...';

	/// en: '16384 (Default)'
	String get pbkdf16384 => '16384 (Default)';

	/// en: '32768 (Stronger)'
	String get pbkdf32768 => '32768 (Stronger)';

	/// en: '65536 (Paranoid)'
	String get pbkdf65536 => '65536 (Paranoid)';

	/// en: '131072 (Extreme)'
	String get pbkdf131072 => '131072 (Extreme)';

	/// en: '1024 bytes (Legacy)'
	String get block1024 => '1024 bytes (Legacy)';

	/// en: '4096 bytes (Default)'
	String get block4096 => '4096 bytes (Default)';

	/// en: '8192 bytes'
	String get block8192 => '8192 bytes';

	/// en: '65536 bytes (Max)'
	String get block65536 => '65536 bytes (Max)';

	/// en: 'Enter a password to encrypt your notes.'
	String get createVaultContent => 'Enter a password to encrypt your notes.';

	/// en: 'Confirm Password'
	String get confirmPassword => 'Confirm Password';

	/// en: 'Password must be at least 6 characters'
	String get passwordMinLength => 'Password must be at least 6 characters';

	/// en: 'Advanced Security Options'
	String get advancedSecurityOptions => 'Advanced Security Options';

	/// en: 'Backup Vault'
	String get backupVault => 'Backup Vault';

	/// en: 'Backup Data'
	String get backupData => 'Backup Data';

	/// en: 'Export encrypted vault as a zip archive'
	String get backupVaultSubtitle => 'Export encrypted vault as a zip archive';

	/// en: 'Export notes, settings, and metadata as a zip archive'
	String get backupDataSubtitle => 'Export notes, settings, and metadata as a zip archive';

	/// en: 'Restore Vault'
	String get restoreVault => 'Restore Vault';

	/// en: 'Restore Data'
	String get restoreData => 'Restore Data';

	/// en: 'Replace vault with a backup archive'
	String get restoreVaultSubtitle => 'Replace vault with a backup archive';

	/// en: 'Replace notes, settings, and metadata with a backup archive'
	String get restoreDataSubtitle => 'Replace notes, settings, and metadata with a backup archive';

	/// en: 'Your encrypted vault backup has been saved. The vault is now locked and must be unlocked to continue.'
	String get backupCompleteVault => 'Your encrypted vault backup has been saved. The vault is now locked and must be unlocked to continue.';

	/// en: 'Your notes, settings, and metadata have been backed up.'
	String get backupCompleteData => 'Your notes, settings, and metadata have been backed up.';

	/// en: 'Your notes, settings, and metadata have been restored. The app may need to restart to apply changes.'
	String get restoreCompleteData => 'Your notes, settings, and metadata have been restored. The app may need to restart to apply changes.';

	/// en: 'Vault restored successfully. Please unlock your vault to access notes.'
	String get restoreCompleteVault => 'Vault restored successfully. Please unlock your vault to access notes.';

	/// en: 'Backup Failed: $error'
	String backupFailed({required Object error}) => 'Backup Failed: ${error}';

	/// en: 'Restore Failed: $error'
	String restoreFailed({required Object error}) => 'Restore Failed: ${error}';

	/// en: 'Restore Backup'
	String get restoreBackup => 'Restore Backup';

	/// en: 'This will replace your current notes, settings, and metadata with the backup contents. Continue?'
	String get restoreDataConfirm => 'This will replace your current notes, settings, and metadata with the backup contents. Continue?';

	/// en: 'This will replace your current vault with the backup contents. Continue?'
	String get restoreVaultConfirm => 'This will replace your current vault with the backup contents. Continue?';

	/// en: 'File name'
	String get fileName => 'File name';
}

// Path: toolbar
class Translations$toolbar$en {
	Translations$toolbar$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Derivative'
	String get derivative => 'Derivative';

	/// en: 'Integral'
	String get integral => 'Integral';

	/// en: '2D'
	String get mode2d => '2D';

	/// en: '3D'
	String get mode3d => '3D';

	/// en: 'Calculus graph with legend saved!'
	String get calculusGraphSaved => 'Calculus graph with legend saved!';

	/// en: 'Add New Surface'
	String get addNewSurface => 'Add New Surface';

	/// en: 'Add New Field'
	String get addNewField => 'Add New Field';

	/// en: 'Add New Function'
	String get addNewFunction => 'Add New Function';

	/// en: '2D system (x, y)'
	String get system2d => '2D system (x, y)';

	/// en: '3D system (x, y, z)'
	String get system3d => '3D system (x, y, z)';

	/// en: 'Play'
	String get play => 'Play';

	/// en: 'Stop'
	String get stop => 'Stop';

	/// en: 'Clear'
	String get clear => 'Clear';

	/// en: 'Copy values'
	String get copyValues => 'Copy values';

	/// en: 'Save image'
	String get saveImage => 'Save image';

	/// en: 'Save image + metadata'
	String get saveImageMetadata => 'Save image + metadata';

	/// en: 'Start'
	String get start => 'Start';

	/// en: 'Start cap'
	String get startCap => 'Start cap';

	/// en: 'End'
	String get end => 'End';

	/// en: 'End cap'
	String get endCap => 'End cap';

	/// en: 'Simulate pressure'
	String get simulatePressure => 'Simulate pressure';

	/// en: 'Complete'
	String get complete => 'Complete';

	/// en: 'Save preset'
	String get savePreset => 'Save preset';

	/// en: 'Update preset'
	String get updatePreset => 'Update preset';

	/// en: 'Delete preset'
	String get deletePreset => 'Delete preset';

	/// en: 'Fill'
	String get fill => 'Fill';

	/// en: 'Mode'
	String get mode => 'Mode';

	/// en: 'Erase stroke'
	String get eraseStroke => 'Erase stroke';

	/// en: 'Erase area'
	String get eraseArea => 'Erase area';

	/// en: 'Plot'
	String get plot => 'Plot';

	/// en: '2D (Cartesian)'
	String get plot2dCartesian => '2D (Cartesian)';

	/// en: '2D (Polar)'
	String get plot2dPolar => '2D (Polar)';

	/// en: '3D Surface (Cartesian)'
	String get plot3dSurface => '3D Surface (Cartesian)';

	/// en: '3D Surface (Spherical)'
	String get plot3dSpherical => '3D Surface (Spherical)';

	/// en: 'Vector Field 2D'
	String get vectorField2d => 'Vector Field 2D';

	/// en: 'Vector Field 3D (slice)'
	String get vectorField3d => 'Vector Field 3D (slice)';

	/// en: 'Find roots'
	String get findRoots => 'Find roots';

	/// en: 'Find min'
	String get findMin => 'Find min';

	/// en: 'Find max'
	String get findMax => 'Find max';

	/// en: 'Show asymptotes'
	String get showAsymptotes => 'Show asymptotes';

	/// en: 'Find saddle'
	String get findSaddle => 'Find saddle';

	/// en: '2D f(x)'
	String get f2d => '2D f(x)';

	/// en: '3D f(x,y)'
	String get f3d => '3D f(x,y)';
}

// Path: backup
class Translations$backup$en {
	Translations$backup$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Backing up notes...'
	String get notificationTitle => 'Backing up notes...';

	/// en: '$current / $total assets synced'
	String notificationBody({required Object current, required Object total}) => '${current} / ${total} assets synced';

	/// en: 'Restoring backup...'
	String get restoreProgressTitle => 'Restoring backup...';
}

// Path: home.folderColor
class Translations$home$folderColor$en {
	Translations$home$folderColor$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Change color'
	String get changeColor => 'Change color';

	/// en: 'Choose color'
	String get chooseColor => 'Choose color';

	/// en: 'Reset color'
	String get reset => 'Reset color';
}

// Path: home.sortNames
class Translations$home$sortNames$en {
	Translations$home$sortNames$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Sort'
	String get sort => 'Sort';

	/// en: 'Alphabetical'
	String get alphabetical => 'Alphabetical';

	/// en: 'Last modified'
	String get lastModified => 'Last modified';

	/// en: 'Size on disk'
	String get sizeOnDisk => 'Size on disk';

	/// en: 'Increasing'
	String get increasing => 'Increasing';
}

// Path: home.tabs
class Translations$home$tabs$en {
	Translations$home$tabs$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'Home'
	String get home => 'Home';

	/// en: 'Browse'
	String get browse => 'Browse';

	/// en: 'Whiteboard'
	String get whiteboard => 'Whiteboard';

	/// en: 'Settings'
	String get settings => 'Settings';
}

// Path: home.titles
class Translations$home$titles$en {
	Translations$home$titles$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Search'
	String get search => 'Search';

	/// en: 'Recent notes'
	String get home => 'Recent notes';

	/// en: 'Browse'
	String get browse => 'Browse';

	/// en: 'Whiteboard'
	String get whiteboard => 'Whiteboard';

	/// en: 'Settings'
	String get settings => 'Settings';
}

// Path: home.graph
class Translations$home$graph$en {
	Translations$home$graph$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Showing $shown of $total notes'
	String showingNotes({required Object shown, required Object total}) => 'Showing ${shown} of ${total} notes';

	/// en: 'Search by name or tag to set root'
	String get rootSearchHint => 'Search by name or tag to set root';

	/// en: 'All notes'
	String get clearRoot => 'All notes';

	/// en: 'Select root'
	String get selectRoot => 'Select root';
}

// Path: home.tooltips
class Translations$home$tooltips$en {
	Translations$home$tooltips$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Toggle view mode'
	String get viewMode => 'Toggle view mode';

	/// en: 'Tree view'
	String get treeView => 'Tree view';

	/// en: 'Folder view'
	String get folderView => 'Folder view';

	/// en: 'New note'
	String get newNote => 'New note';

	/// en: 'Show update dialog'
	String get showUpdateDialog => 'Show update dialog';

	/// en: 'Export note'
	String get exportNote => 'Export note';
}

// Path: home.create
class Translations$home$create$en {
	Translations$home$create$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New note'
	String get newNote => 'New note';

	/// en: 'Import note'
	String get importNote => 'Import note';

	/// en: 'Infinite note'
	String get infiniteNote => 'Infinite note';
}

// Path: home.fileList
class Translations$home$fileList$en {
	Translations$home$fileList$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Size'
	String get metaSize => 'Size';

	/// en: 'Modified'
	String get metaModified => 'Modified';

	/// en: 'Accessed'
	String get metaAccessed => 'Accessed';

	/// en: 'Notes inside'
	String get metaNotesInside => 'Notes inside';

	/// en: 'Not opened in the app yet'
	String get accessedUnavailableVault => 'Not opened in the app yet';
}

// Path: home.newFolder
class Translations$home$newFolder$en {
	Translations$home$newFolder$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'New folder'
	String get newFolder => 'New folder';

	/// en: 'Folder name'
	String get folderName => 'Folder name';

	/// en: 'Create'
	String get create => 'Create';

	/// en: 'Folder name can't be empty'
	String get folderNameEmpty => 'Folder name can\'t be empty';

	/// en: 'Folder name can't contain a slash'
	String get folderNameContainsSlash => 'Folder name can\'t contain a slash';

	/// en: 'Folder already exists'
	String get folderNameExists => 'Folder already exists';
}

// Path: home.renameNote
class Translations$home$renameNote$en {
	Translations$home$renameNote$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Rename note'
	String get renameNote => 'Rename note';

	/// en: 'Note name'
	String get noteName => 'Note name';

	/// en: 'Rename'
	String get rename => 'Rename';

	/// en: 'Note name can't be empty'
	String get noteNameEmpty => 'Note name can\'t be empty';

	/// en: 'Note name can't contain a slash'
	String get noteNameContainsSlash => 'Note name can\'t contain a slash';

	/// en: 'A note with this name already exists'
	String get noteNameExists => 'A note with this name already exists';
}

// Path: home.moveNote
class Translations$home$moveNote$en {
	Translations$home$moveNote$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Move note'
	String get moveNote => 'Move note';

	/// en: 'Move $n notes'
	String moveNotes({required Object n}) => 'Move ${n} notes';

	/// en: 'Move $f'
	String moveName({required Object f}) => 'Move ${f}';

	/// en: 'Move'
	String get move => 'Move';

	/// en: 'Note will be renamed to $newName'
	String renamedTo({required Object newName}) => 'Note will be renamed to ${newName}';

	/// en: 'The following notes will be renamed:'
	String get multipleRenamedTo => 'The following notes will be renamed:';

	/// en: '$n notes will be renamed to avoid conflicts'
	String numberRenamedTo({required Object n}) => '${n} notes will be renamed to avoid conflicts';
}

// Path: home.renameFolder
class Translations$home$renameFolder$en {
	Translations$home$renameFolder$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Rename folder'
	String get renameFolder => 'Rename folder';

	/// en: 'Folder name'
	String get folderName => 'Folder name';

	/// en: 'Rename'
	String get rename => 'Rename';

	/// en: 'Folder name can't be empty'
	String get folderNameEmpty => 'Folder name can\'t be empty';

	/// en: 'Folder name can't contain a slash'
	String get folderNameContainsSlash => 'Folder name can\'t contain a slash';

	/// en: 'A folder with this name already exists'
	String get folderNameExists => 'A folder with this name already exists';
}

// Path: home.deleteFolder
class Translations$home$deleteFolder$en {
	Translations$home$deleteFolder$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Delete folder'
	String get deleteFolder => 'Delete folder';

	/// en: 'Delete $f'
	String deleteName({required Object f}) => 'Delete ${f}';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Also delete all notes inside this folder'
	String get alsoDeleteContents => 'Also delete all notes inside this folder';
}

// Path: home.moveFolder
class Translations$home$moveFolder$en {
	Translations$home$moveFolder$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Move folder'
	String get moveFolder => 'Move folder';

	/// en: 'Move $f'
	String moveName({required Object f}) => 'Move ${f}';

	/// en: 'Move'
	String get move => 'Move';

	/// en: 'Folder will be renamed to $newName'
	String renamedTo({required Object newName}) => 'Folder will be renamed to ${newName}';

	/// en: 'Cannot move folder here'
	String get cantMoveHere => 'Cannot move folder here';
}

// Path: sentry.consent
class Translations$sentry$consent$en {
	Translations$sentry$consent$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Help improve Saber?'
	String get title => 'Help improve Saber?';

	late final Translations$sentry$consent$description$en description = Translations$sentry$consent$description$en.internal(_root);
	late final Translations$sentry$consent$answers$en answers = Translations$sentry$consent$answers$en.internal(_root);
}

// Path: settings.prefLabels
class Translations$settings$prefLabels$en {
	Translations$settings$prefLabels$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Stroke stabilization'
	String get strokeStabilization => 'Stroke stabilization';

	/// en: 'Flat edge'
	String get flatEdge => 'Flat edge';

	/// en: 'Flat'
	String get highlighterCapFlat => 'Flat';

	/// en: 'Round'
	String get highlighterCapRound => 'Round';

	/// en: 'Stabilization amount'
	String get strokeStabilizationAmount => 'Stabilization amount';

	/// en: 'Stroke prediction'
	String get strokePrediction => 'Stroke prediction';

	/// en: 'Prediction strength'
	String get strokePredictionAmount => 'Prediction strength';

	/// en: 'Toolbar color slots'
	String get toolbarColorSlotsCount => 'Toolbar color slots';

	/// en: 'Pen size presets'
	String get penSizePresetCount => 'Pen size presets';

	/// en: 'Preset'
	String get penSizePresetSlot => 'Preset';

	/// en: 'Theme variant'
	String get themeVariant => 'Theme variant';

	/// en: 'Language'
	String get locale => 'Language';

	/// en: 'App theme'
	String get appTheme => 'App theme';

	/// en: 'Theme type'
	String get platform => 'Theme type';

	/// en: 'Layout type'
	String get layoutSize => 'Layout type';

	/// en: 'Custom accent color'
	String get customAccentColor => 'Custom accent color';

	/// en: 'Atkinson Hyperlegible font'
	String get hyperlegibleFont => 'Atkinson Hyperlegible font';

	/// en: 'Check for Saber updates'
	String get shouldCheckForUpdates => 'Check for Saber updates';

	/// en: 'Faster updates'
	String get shouldAlwaysAlertForUpdates => 'Faster updates';

	/// en: 'Allow insecure connections'
	String get allowInsecureConnections => 'Allow insecure connections';

	/// en: 'Toolbar position'
	String get editorToolbarAlignment => 'Toolbar position';

	/// en: 'Show the toolbar in fullscreen mode'
	String get editorToolbarShowInFullscreen => 'Show the toolbar in fullscreen mode';

	/// en: 'Invert notes in dark mode'
	String get editorAutoInvert => 'Invert notes in dark mode';

	/// en: 'Prefer greyscale colors'
	String get preferGreyscale => 'Prefer greyscale colors';

	/// en: 'Maximum image size'
	String get maxImageSize => 'Maximum image size';

	/// en: 'Auto-clear the whiteboard'
	String get autoClearWhiteboardOnExit => 'Auto-clear the whiteboard';

	/// en: 'Auto-disable the eraser'
	String get disableEraserAfterUse => 'Auto-disable the eraser';

	/// en: 'Hide the finger drawing toggle'
	String get hideFingerDrawingToggle => 'Hide the finger drawing toggle';

	/// en: 'Auto-disable finger drawing'
	String get autoDisableFingerDrawingWhenStylusDetected => 'Auto-disable finger drawing';

	/// en: 'Prompt you to rename new notes'
	String get editorPromptRename => 'Prompt you to rename new notes';

	/// en: 'Don't save preset colors in recent colors'
	String get recentColorsDontSavePresets => 'Don\'t save preset colors in recent colors';

	/// en: 'How many recent colors to store'
	String get recentColorsLength => 'How many recent colors to store';

	/// en: 'Print page indicators'
	String get printPageIndicators => 'Print page indicators';

	/// en: 'Auto-save'
	String get autosave => 'Auto-save';

	/// en: 'Shape recognition delay'
	String get shapeRecognitionDelay => 'Shape recognition delay';

	/// en: 'Auto straighten lines'
	String get autoStraightenLines => 'Auto straighten lines';

	/// en: 'Simplified home layout'
	String get simplifiedHomeLayout => 'Simplified home layout';

	/// en: 'Custom Saber folder'
	String get customDataDir => 'Custom Saber folder';

	/// en: 'Error reporting'
	String get sentry => 'Error reporting';
}

// Path: settings.prefDescriptions
class Translations$settings$prefDescriptions$en {
	Translations$settings$prefDescriptions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Smooths out your handwriting'
	String get strokeStabilization => 'Smooths out your handwriting';

	/// en: 'Draws a short ink tip slightly ahead of the stylus while you move (not saved in the note; reduces perceived lag)'
	String get strokePrediction => 'Draws a short ink tip slightly ahead of the stylus while you move (not saved in the note; reduces perceived lag)';

	/// en: 'How far ahead to extrapolate while drawing'
	String get strokePredictionAmount => 'How far ahead to extrapolate while drawing';

	/// en: 'Number of colors to show in the toolbar'
	String get toolbarColorSlotsCount => 'Number of colors to show in the toolbar';

	/// en: 'Number of stroke-width presets shown in the editor toolbar'
	String get penSizePresetCount => 'Number of stroke-width presets shown in the editor toolbar';

	/// en: 'Color scheme variant'
	String get themeVariant => 'Color scheme variant';

	/// en: 'Increases legibility for users with low vision'
	String get hyperlegibleFont => 'Increases legibility for users with low vision';

	/// en: '(Not recommended) Allow Saber to connect to servers with self-signed/untrusted certificates'
	String get allowInsecureConnections => '(Not recommended) Allow Saber to connect to servers with self-signed/untrusted certificates';

	/// en: 'For e-ink displays'
	String get preferGreyscale => 'For e-ink displays';

	/// en: 'Clears the whiteboard after you exit the app'
	String get autoClearWhiteboardOnExit => 'Clears the whiteboard after you exit the app';

	/// en: 'Automatically switches back to the pen after using the eraser'
	String get disableEraserAfterUse => 'Automatically switches back to the pen after using the eraser';

	/// en: 'Larger images will be compressed'
	String get maxImageSize => 'Larger images will be compressed';

	late final Translations$settings$prefDescriptions$hideFingerDrawing$en hideFingerDrawing = Translations$settings$prefDescriptions$hideFingerDrawing$en.internal(_root);

	/// en: 'Turn off finger drawing when a stylus is detected'
	String get autoDisableFingerDrawingWhenStylusDetected => 'Turn off finger drawing when a stylus is detected';

	/// en: 'You can always rename notes later'
	String get editorPromptRename => 'You can always rename notes later';

	/// en: 'Show page indicators in exports'
	String get printPageIndicators => 'Show page indicators in exports';

	/// en: 'Auto-save after a short delay, or never'
	String get autosave => 'Auto-save after a short delay, or never';

	/// en: 'Hold at end of stroke for this long to recognize and replace with a clean shape (line, rectangle, circle, etc.). Set to Never to disable.'
	String get shapeRecognitionDelay => 'Hold at end of stroke for this long to recognize and replace with a clean shape (line, rectangle, circle, etc.). Set to Never to disable.';

	/// en: 'With highlighter, replace straight strokes with a clean line.'
	String get autoStraightenLines => 'With highlighter, replace straight strokes with a clean line.';

	/// en: 'Sets a fixed height for each note preview'
	String get simplifiedHomeLayout => 'Sets a fixed height for each note preview';

	/// en: 'Tell me about updates as soon as they're available'
	String get shouldAlwaysAlertForUpdates => 'Tell me about updates as soon as they\'re available';

	late final Translations$settings$prefDescriptions$sentry$en sentry = Translations$settings$prefDescriptions$sentry$en.internal(_root);
}

// Path: settings.themeVariants
class Translations$settings$themeVariants$en {
	Translations$settings$themeVariants$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Material'
	String get material => 'Material';

	/// en: 'AMOLED'
	String get amoled => 'AMOLED';
}

// Path: settings.prefCategories
class Translations$settings$prefCategories$en {
	Translations$settings$prefCategories$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Privacy & Security'
	String get security => 'Privacy & Security';

	/// en: 'General'
	String get general => 'General';

	/// en: 'Writing'
	String get writing => 'Writing';

	/// en: 'Editor'
	String get editor => 'Editor';

	/// en: 'Performance'
	String get performance => 'Performance';

	/// en: 'Advanced'
	String get advanced => 'Advanced';
}

// Path: settings.noteInkDefaults
class Translations$settings$noteInkDefaults$en {
	Translations$settings$noteInkDefaults$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Note & ink defaults'
	String get sectionTitle => 'Note & ink defaults';

	/// en: 'Change note defaults'
	String get changeNoteDefaults => 'Change note defaults';

	/// en: 'Pattern, spacing, colors, and margins for new notes'
	String get changeNoteDefaultsSubtitle => 'Pattern, spacing, colors, and margins for new notes';

	/// en: 'Change ink defaults'
	String get changeInkDefaults => 'Change ink defaults';

	/// en: 'Toolbar colors, stroke widths, and palettes'
	String get changeInkDefaultsSubtitle => 'Toolbar colors, stroke widths, and palettes';

	/// en: 'Note defaults'
	String get noteDefaultsTitle => 'Note defaults';

	/// en: 'Live preview — used when you create a note'
	String get noteDefaultsSubtitle => 'Live preview — used when you create a note';

	/// en: 'Ink defaults'
	String get inkDefaultsTitle => 'Ink defaults';

	/// en: 'Palettes and toolbar colors'
	String get inkDefaultsSubtitle => 'Palettes and toolbar colors';

	/// en: 'Palette'
	String get activePalette => 'Palette';

	/// en: 'Palette'
	String get palettePickerLabel => 'Palette';

	/// en: 'New palette from current'
	String get savePaletteAsNew => 'New palette from current';

	/// en: 'New palette'
	String get savePaletteAsNewShort => 'New palette';

	/// en: 'Save palette'
	String get savePaletteAsNewTitle => 'Save palette';

	/// en: 'Tap a swatch to recolor toolbar slots.'
	String get toolbarSlotsHint => 'Tap a swatch to recolor toolbar slots.';

	/// en: 'Rename palette'
	String get renamePalette => 'Rename palette';

	/// en: 'Rename palette'
	String get renamePaletteTitle => 'Rename palette';

	/// en: 'Name'
	String get paletteNameHint => 'Name';

	/// en: 'Remove this palette? Toolbar colors stay until you choose another palette.'
	String get deletePaletteConfirm => 'Remove this palette? Toolbar colors stay until you choose another palette.';

	/// en: 'Colors in toolbar'
	String get toolbarSlotsDropdownLabel => 'Colors in toolbar';

	/// en: 'Toolbar slot $index'
	String toolbarSlotColor({required Object index}) => 'Toolbar slot ${index}';

	/// en: 'Stroke width presets'
	String get penSizePresetCountLabel => 'Stroke width presets';
}

// Path: settings.themeModes
class Translations$settings$themeModes$en {
	Translations$settings$themeModes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'System'
	String get system => 'System';

	/// en: 'Light'
	String get light => 'Light';

	/// en: 'Dark'
	String get dark => 'Dark';
}

// Path: settings.layoutSizes
class Translations$settings$layoutSizes$en {
	Translations$settings$layoutSizes$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Auto'
	String get auto => 'Auto';

	/// en: 'Phone'
	String get phone => 'Phone';

	/// en: 'Tablet'
	String get tablet => 'Tablet';
}

// Path: settings.accentColorPicker
class Translations$settings$accentColorPicker$en {
	Translations$settings$accentColorPicker$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pick a color'
	String get pickAColor => 'Pick a color';
}

// Path: settings.reset
class Translations$settings$reset$en {
	Translations$settings$reset$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Reset this setting?'
	String get title => 'Reset this setting?';

	/// en: 'Reset'
	String get button => 'Reset';
}

// Path: settings.customDataDir
class Translations$settings$customDataDir$en {
	Translations$settings$customDataDir$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Cancel'
	String get cancel => 'Cancel';

	/// en: 'Select'
	String get select => 'Select';

	/// en: 'Selected folder must be empty'
	String get mustBeEmpty => 'Selected folder must be empty';

	/// en: 'Make sure syncing is complete before changing the folder'
	String get mustBeDoneSyncing => 'Make sure syncing is complete before changing the folder';

	/// en: 'This feature is currently only for developers. Using it will likely result in data loss.'
	String get unsupported => 'This feature is currently only for developers. Using it will likely result in data loss.';
}

// Path: login.form
class Translations$login$form$en {
	Translations$login$form$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'By logging in, you agree to the ${linkToPrivacyPolicy(Privacy Policy)}.'
	TextSpan agreeToPrivacyPolicy({required InlineSpanBuilder linkToPrivacyPolicy}) => TextSpan(children: [
		const TextSpan(text: 'By logging in, you agree to the '),
		linkToPrivacyPolicy('Privacy Policy'),
		const TextSpan(text: '.'),
	]);
}

// Path: login.status
class Translations$login$status$en {
	Translations$login$status$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Logged out'
	String get loggedOut => 'Logged out';

	/// en: 'Tap to log in with Nextcloud'
	String get tapToLogin => 'Tap to log in with Nextcloud';

	/// en: 'Hi, $u!'
	String hi({required Object u}) => 'Hi, ${u}!';

	/// en: 'Almost ready for syncing, tap to finish logging in'
	String get almostDone => 'Almost ready for syncing, tap to finish logging in';

	/// en: 'Logged in with Nextcloud'
	String get loggedIn => 'Logged in with Nextcloud';
}

// Path: login.ncLoginStep
class Translations$login$ncLoginStep$en {
	Translations$login$ncLoginStep$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Choose where you want to store your data:'
	String get whereToStoreData => 'Choose where you want to store your data:';

	/// en: 'Saber's Nextcloud server'
	String get saberNcServer => 'Saber\'s Nextcloud server';

	/// en: 'Other Nextcloud server'
	String get otherNcServer => 'Other Nextcloud server';

	/// en: 'Server URL'
	String get serverUrl => 'Server URL';

	/// en: 'Login with Saber'
	String get loginWithSaber => 'Login with Saber';

	/// en: 'Login with Nextcloud'
	String get loginWithNextcloud => 'Login with Nextcloud';

	late final Translations$login$ncLoginStep$loginFlow$en loginFlow = Translations$login$ncLoginStep$loginFlow$en.internal(_root);
}

// Path: login.encLoginStep
class Translations$login$encLoginStep$en {
	Translations$login$encLoginStep$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'To protect your data, please enter your encryption password:'
	String get enterEncPassword => 'To protect your data, please enter your encryption password:';

	/// en: 'New to Saber? Just enter a new encryption password.'
	String get newToSaber => 'New to Saber? Just enter a new encryption password.';

	/// en: 'Encryption password'
	String get encPassword => 'Encryption password';

	/// en: 'Frequently asked questions'
	String get encFaqTitle => 'Frequently asked questions';

	/// en: 'Decryption failed with the provided password. Please try entering it again.'
	String get wrongEncPassword => 'Decryption failed with the provided password. Please try entering it again.';

	/// en: 'Something went wrong connecting to the server. Please try again later.'
	String get connectionFailed => 'Something went wrong connecting to the server. Please try again later.';

	List<dynamic> get encFaq => [
		Translations$login$encLoginStep$encFaq$0$en.internal(_root),
		Translations$login$encLoginStep$encFaq$1$en.internal(_root),
		Translations$login$encLoginStep$encFaq$2$en.internal(_root),
	];
}

// Path: profile.quickLinks
class Translations$profile$quickLinks$en {
	Translations$profile$quickLinks$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Server homepage'
	String get serverHomepage => 'Server homepage';

	/// en: 'Delete account'
	String get deleteAccount => 'Delete account';
}

// Path: profile.faq.0
class Translations$profile$faq$0$en {
	Translations$profile$faq$0$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Will I lose my notes if I log out?'
	String get q => 'Will I lose my notes if I log out?';

	/// en: 'No. Your notes will remain both on your device and on the server. They won't be synced with the server until you log back in. Make sure syncing is complete before logging out so you don't lose any data (see the sync progress on the home screen).'
	String get a => 'No. Your notes will remain both on your device and on the server. They won\'t be synced with the server until you log back in. Make sure syncing is complete before logging out so you don\'t lose any data (see the sync progress on the home screen).';
}

// Path: profile.faq.1
class Translations$profile$faq$1$en {
	Translations$profile$faq$1$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'How do I change my Nextcloud password?'
	String get q => 'How do I change my Nextcloud password?';

	/// en: 'Go to your server website and log in. Then go to Settings > Security > Change password. You'll need to log out and log back in to Saber after changing your password.'
	String get a => 'Go to your server website and log in. Then go to Settings > Security > Change password. You\'ll need to log out and log back in to Saber after changing your password.';
}

// Path: profile.faq.2
class Translations$profile$faq$2$en {
	Translations$profile$faq$2$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'How do I change my encryption password?'
	String get q => 'How do I change my encryption password?';

	/// en: '0. Make sure syncing is complete (see the sync progress on the home screen). 1. Log out of Saber. 2. Go to your server website and delete your 'Saber' folder. This will delete all your notes from the server. 3. Log back in to Saber. You can choose a new encryption password when logging in. 4. Don't forget to log out and log back in to Saber on your other devices too.'
	String get a => '0. Make sure syncing is complete (see the sync progress on the home screen).\n1. Log out of Saber.\n2. Go to your server website and delete your \'Saber\' folder. This will delete all your notes from the server.\n3. Log back in to Saber. You can choose a new encryption password when logging in.\n4. Don\'t forget to log out and log back in to Saber on your other devices too.';
}

// Path: profile.faq.3
class Translations$profile$faq$3$en {
	Translations$profile$faq$3$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'How can I delete my account?'
	String get q => 'How can I delete my account?';

	/// en: 'Tap on the "Delete account" button above, and login if needed. If you are using the official Saber server, your account will be deleted after a 1 week grace period. You can contact me at adilhanney@disroot.org during this period to cancel the deletion. If you are using a third party server, there might not be an option to delete your account: you'll need to consult the server's privacy policy for more information.'
	String get a => 'Tap on the "${_root.profile.quickLinks.deleteAccount}" button above, and login if needed.\nIf you are using the official Saber server, your account will be deleted after a 1 week grace period. You can contact me at adilhanney@disroot.org during this period to cancel the deletion.\nIf you are using a third party server, there might not be an option to delete your account: you\'ll need to consult the server\'s privacy policy for more information.';
}

// Path: editor.navigation
class Translations$editor$navigation$en {
	Translations$editor$navigation$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Notes'
	String get title => 'Notes';

	/// en: 'Outlines'
	String get pdfOutlines => 'Outlines';

	/// en: 'No outline entries'
	String get noPdfOutlineEntries => 'No outline entries';

	/// en: 'Add outlines to bookmark pages in this note. They are included when you export as PDF.'
	String get noOutlineEntriesHint => 'Add outlines to bookmark pages in this note. They are included when you export as PDF.';

	/// en: 'Add outline for current page'
	String get addOutlineForPage => 'Add outline for current page';

	/// en: 'Rename outline'
	String get renameOutline => 'Rename outline';

	/// en: 'Delete outline'
	String get deleteOutline => 'Delete outline';

	/// en: 'Title'
	String get outlineTitle => 'Title';

	/// en: 'Outline actions'
	String get outlineActions => 'Outline actions';

	/// en: 'First page'
	String get firstPage => 'First page';

	/// en: 'Last page'
	String get lastPage => 'Last page';

	/// en: 'Go to page'
	String get goToPage => 'Go to page';

	/// en: 'Page number'
	String get pageNumber => 'Page number';

	/// en: 'Page $total'
	String pageNumberHint({required Object total}) => 'Page ${total}';
}

// Path: editor.pens
class Translations$editor$pens$en {
	Translations$editor$pens$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Calligraphy pen'
	String get calligraphyPen => 'Calligraphy pen';

	/// en: 'Fountain pen'
	String get fountainPen => 'Fountain pen';

	/// en: 'Ballpoint pen'
	String get ballpointPen => 'Ballpoint pen';

	/// en: 'Advanced pen'
	String get advancedPen => 'Advanced pen';

	/// en: 'Advanced pencil'
	String get advancedPencil => 'Advanced pencil';

	/// en: 'Highlighter'
	String get highlighter => 'Highlighter';

	/// en: 'Shape pen'
	String get shapePen => 'Shape pen';

	/// en: 'Laser pointer'
	String get laserPointer => 'Laser pointer';
}

// Path: editor.selectionBar
class Translations$editor$selectionBar$en {
	Translations$editor$selectionBar$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Copy'
	String get copy => 'Copy';

	/// en: 'Cut'
	String get cut => 'Cut';

	/// en: 'Paste'
	String get paste => 'Paste';

	/// en: 'Move'
	String get move => 'Move';

	/// en: 'Delete'
	String get delete => 'Delete';

	/// en: 'Duplicate'
	String get duplicate => 'Duplicate';

	/// en: 'Share'
	String get share => 'Share';

	/// en: 'Share as SVG'
	String get shareAsSvg => 'Share as SVG';

	/// en: 'Change color'
	String get changeColor => 'Change color';

	/// en: 'Change stroke type'
	String get changeStrokeType => 'Change stroke type';

	/// en: 'Change stroke type'
	String get changeStrokeTypeTitle => 'Change stroke type';

	/// en: 'Convert selected strokes to another pen.'
	String get changeStrokeTypeHint => 'Convert selected strokes to another pen.';
}

// Path: editor.toolbar
class Translations$editor$toolbar$en {
	Translations$editor$toolbar$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Toggle colors'
	String get toggleColors => 'Toggle colors';

	/// en: 'Select'
	String get select => 'Select';

	/// en: 'Toggle eraser'
	String get toggleEraser => 'Toggle eraser';

	/// en: 'Images'
	String get photo => 'Images';

	/// en: 'Text'
	String get text => 'Text';

	/// en: 'Toggle finger drawing'
	String get toggleFingerDrawing => 'Toggle finger drawing';

	/// en: 'Undo'
	String get undo => 'Undo';

	/// en: 'Redo'
	String get redo => 'Redo';

	/// en: 'Export'
	String get export => 'Export';

	/// en: 'Export as:'
	String get exportAs => 'Export as:';

	/// en: 'Toggle fullscreen'
	String get fullscreen => 'Toggle fullscreen';

	/// en: 'Region screenshot'
	String get regionScreenshot => 'Region screenshot';

	/// en: 'Drag to select an area'
	String get regionScreenshotHint => 'Drag to select an area';

	/// en: 'Share or copy screenshot?'
	String get regionScreenshotTitle => 'Share or copy screenshot?';

	/// en: 'Share with another app, or copy the image to the clipboard.'
	String get regionScreenshotBody => 'Share with another app, or copy the image to the clipboard.';

	/// en: 'Share'
	String get regionScreenshotShare => 'Share';

	/// en: 'Copy to clipboard'
	String get regionScreenshotCopy => 'Copy to clipboard';

	/// en: 'Selection too small'
	String get regionScreenshotTooSmall => 'Selection too small';

	/// en: 'Failed to capture screenshot'
	String get regionScreenshotFailed => 'Failed to capture screenshot';
}

// Path: editor.penOptions
class Translations$editor$penOptions$en {
	Translations$editor$penOptions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Size'
	String get size => 'Size';

	/// en: 'Opacity'
	String get opacity => 'Opacity';

	/// en: 'Thinning'
	String get thinning => 'Thinning';

	/// en: 'Smoothing'
	String get smoothing => 'Smoothing';

	/// en: 'Streamline'
	String get streamline => 'Streamline';

	/// en: 'Pressure sensitivity'
	String get pressureSensitivity => 'Pressure sensitivity';

	/// en: 'Velocity thinning'
	String get velocityThinning => 'Velocity thinning';

	/// en: 'Min width ratio'
	String get minSizeRatio => 'Min width ratio';

	/// en: 'Max width ratio'
	String get maxSizeRatio => 'Max width ratio';

	/// en: 'Start taper'
	String get startTaper => 'Start taper';

	/// en: 'End taper'
	String get endTaper => 'End taper';

	/// en: 'Width easing'
	String get easing => 'Width easing';

	/// en: 'Start taper easing'
	String get startEasing => 'Start taper easing';

	/// en: 'End taper easing'
	String get endEasing => 'End taper easing';

	/// en: 'Neon stroke'
	String get neonStroke => 'Neon stroke';

	/// en: 'Preset name'
	String get presetNameHint => 'Preset name';

	/// en: 'Pencil grain'
	String get pencilNoise => 'Pencil grain';

	/// en: 'Fast procedural noise (no image tiles). Defaults are tuned for smooth drawing.'
	String get pencilNoiseHint => 'Fast procedural noise (no image tiles). Defaults are tuned for smooth drawing.';

	/// en: 'Grain size'
	String get noiseGrainScale => 'Grain size';

	/// en: 'Coverage'
	String get noiseThreshold => 'Coverage';

	/// en: 'Contrast'
	String get noiseContrast => 'Contrast';

	/// en: 'Fine speck mix'
	String get noiseFineMix => 'Fine speck mix';

	/// en: 'Reset grain'
	String get resetNoiseDefaults => 'Reset grain';

	/// en: 'Stylus pressure'
	String get pressureMapsTo => 'Stylus pressure';

	/// en: 'Thickness'
	String get pressureToThickness => 'Thickness';

	/// en: 'Coverage'
	String get pressureToCoverage => 'Coverage';

	/// en: 'Shadow'
	String get pencilShadow => 'Shadow';
}

// Path: editor.penSizePresets
class Translations$editor$penSizePresets$en {
	Translations$editor$penSizePresets$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Pen preset $n'
	String editTitle({required Object n}) => 'Pen preset ${n}';

	/// en: 'Applies from editor toolbar presets (double tap a preset chip to tune it.)'
	String get editSubtitle => 'Applies from editor toolbar presets (double tap a preset chip to tune it.)';

	/// en: 'Matches pen modal stroke scale; labels match the toolbar pen slider numbering (around 1.0 to 10.0).'
	String get sameAsPenSlider => 'Matches pen modal stroke scale; labels match the toolbar pen slider numbering (around 1.0 to 10.0).';

	/// en: 'Tap once for preset stroke width; double tap (with editor open) adjusts it for that note.'
	String get tooltip => 'Tap once for preset stroke width; double tap (with editor open) adjusts it for that note.';
}

// Path: editor.colors
class Translations$editor$colors$en {
	Translations$editor$colors$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Color picker'
	String get colorPicker => 'Color picker';

	/// en: 'Custom $b $h'
	String customBrightnessHue({required Object b, required Object h}) => 'Custom ${b} ${h}';

	/// en: 'Custom $h'
	String customHue({required Object h}) => 'Custom ${h}';

	/// en: 'dark'
	String get dark => 'dark';

	/// en: 'light'
	String get light => 'light';

	/// en: 'Black'
	String get black => 'Black';

	/// en: 'Dark grey'
	String get darkGrey => 'Dark grey';

	/// en: 'Grey'
	String get grey => 'Grey';

	/// en: 'Light grey'
	String get lightGrey => 'Light grey';

	/// en: 'White'
	String get white => 'White';

	/// en: 'Red'
	String get red => 'Red';

	/// en: 'Green'
	String get green => 'Green';

	/// en: 'Cyan'
	String get cyan => 'Cyan';

	/// en: 'Blue'
	String get blue => 'Blue';

	/// en: 'Yellow'
	String get yellow => 'Yellow';

	/// en: 'Purple'
	String get purple => 'Purple';

	/// en: 'Pink'
	String get pink => 'Pink';

	/// en: 'Orange'
	String get orange => 'Orange';

	/// en: 'Pastel red'
	String get pastelRed => 'Pastel red';

	/// en: 'Pastel orange'
	String get pastelOrange => 'Pastel orange';

	/// en: 'Pastel yellow'
	String get pastelYellow => 'Pastel yellow';

	/// en: 'Pastel green'
	String get pastelGreen => 'Pastel green';

	/// en: 'Pastel cyan'
	String get pastelCyan => 'Pastel cyan';

	/// en: 'Pastel blue'
	String get pastelBlue => 'Pastel blue';

	/// en: 'Pastel purple'
	String get pastelPurple => 'Pastel purple';

	/// en: 'Pastel pink'
	String get pastelPink => 'Pastel pink';
}

// Path: editor.pdfLoading
class Translations$editor$pdfLoading$en {
	Translations$editor$pdfLoading$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Decrypting PDF…'
	String get decrypting => 'Decrypting PDF…';

	/// en: 'Loading PDF…'
	String get loading => 'Loading PDF…';
}

// Path: editor.vaultPdfLargeRam
class Translations$editor$vaultPdfLargeRam$en {
	Translations$editor$vaultPdfLargeRam$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Allow large PDFs in RAM'
	String get allowLarge => 'Allow large PDFs in RAM';

	/// en: 'PDFs >100MB may load in RAM (risk of crash)'
	String get allowLargeSubtitleOn => 'PDFs >100MB may load in RAM (risk of crash)';

	/// en: 'PDFs >100MB always use temp file (default, safe)'
	String get allowLargeSubtitleOff => 'PDFs >100MB always use temp file (default, safe)';
}

// Path: editor.imageOptions
class Translations$editor$imageOptions$en {
	Translations$editor$imageOptions$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Image options'
	String get title => 'Image options';

	/// en: 'Invertible'
	String get invertible => 'Invertible';

	/// en: 'Download'
	String get download => 'Download';

	/// en: 'Set as background'
	String get setAsBackground => 'Set as background';

	/// en: 'Remove as background'
	String get removeAsBackground => 'Remove as background';

	/// en: 'Delete'
	String get delete => 'Delete';
}

// Path: editor.menu
class Translations$editor$menu$en {
	Translations$editor$menu$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Set cover image'
	String get setCoverImage => 'Set cover image';

	/// en: 'Clear page $page/$totalPages'
	String clearPage({required Object page, required Object totalPages}) => 'Clear page ${page}/${totalPages}';

	/// en: 'Clear all pages'
	String get clearAllPages => 'Clear all pages';

	/// en: 'Insert page below'
	String get insertPage => 'Insert page below';

	/// en: 'Duplicate page'
	String get duplicatePage => 'Duplicate page';

	/// en: 'Delete page'
	String get deletePage => 'Delete page';

	/// en: 'Line height'
	String get lineHeight => 'Line height';

	/// en: 'Also controls the text size for typed notes'
	String get lineHeightDescription => 'Also controls the text size for typed notes';

	/// en: 'Line thickness'
	String get lineThickness => 'Line thickness';

	/// en: 'Background line thickness'
	String get lineThicknessDescription => 'Background line thickness';

	/// en: 'Background image fit'
	String get backgroundImageFit => 'Background image fit';

	/// en: 'Background pattern'
	String get backgroundPattern => 'Background pattern';

	/// en: 'Import'
	String get import => 'Import';

	/// en: 'Watch for updates on the server'
	String get watchServer => 'Watch for updates on the server';

	/// en: 'Editing is disabled while watching the server'
	String get watchServerReadOnly => 'Editing is disabled while watching the server';

	late final Translations$editor$menu$boxFits$en boxFits = Translations$editor$menu$boxFits$en.internal(_root);
	late final Translations$editor$menu$bgPatterns$en bgPatterns = Translations$editor$menu$bgPatterns$en.internal(_root);
}

// Path: editor.newerFileFormat
class Translations$editor$newerFileFormat$en {
	Translations$editor$newerFileFormat$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Read-only mode'
	String get readOnlyMode => 'Read-only mode';

	/// en: 'This note was edited using a newer version of Saber'
	String get title => 'This note was edited using a newer version of Saber';

	/// en: 'Editing this note may result in some information being lost. Do you want to ignore this and edit it anyway?'
	String get subtitle => 'Editing this note may result in some information being lost. Do you want to ignore this and edit it anyway?';

	/// en: 'Allow editing'
	String get allowEditing => 'Allow editing';
}

// Path: editor.quill
class Translations$editor$quill$en {
	Translations$editor$quill$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Type something here...'
	String get typeSomething => 'Type something here...';
}

// Path: editor.hud
class Translations$editor$hud$en {
	Translations$editor$hud$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Unlock zoom'
	String get unlockZoom => 'Unlock zoom';

	/// en: 'Lock zoom'
	String get lockZoom => 'Lock zoom';

	/// en: 'Enable single-finger panning'
	String get unlockSingleFingerPan => 'Enable single-finger panning';

	/// en: 'Disable single-finger panning'
	String get lockSingleFingerPan => 'Disable single-finger panning';

	/// en: 'Unlock panning to horizontal or vertical'
	String get unlockAxisAlignedPan => 'Unlock panning to horizontal or vertical';

	/// en: 'Lock panning to horizontal or vertical'
	String get lockAxisAlignedPan => 'Lock panning to horizontal or vertical';
}

// Path: sentry.consent.description
class Translations$sentry$consent$description$en {
	Translations$sentry$consent$description$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Would you like to automatically report unexpected errors? This helps me identify and fix issues faster.'
	String get question => 'Would you like to automatically report unexpected errors? This helps me identify and fix issues faster.';

	/// en: 'The reports may contain information about the error and your device. I've made every effort to filter out personal data but some may remain.'
	String get scope => 'The reports may contain information about the error and your device. I\'ve made every effort to filter out personal data but some may remain.';

	/// en: 'If you grant consent, error reporting will be enabled after you restart the app.'
	String get currentlyOff => 'If you grant consent, error reporting will be enabled after you restart the app.';

	/// en: 'If you revoke consent, please restart the app to disable error reporting.'
	String get currentlyOn => 'If you revoke consent, please restart the app to disable error reporting.';

	/// en: 'Learn more in the ${link(privacy policy)}.'
	TextSpan learnMoreInPrivacyPolicy({required InlineSpanBuilder link}) => TextSpan(children: [
		const TextSpan(text: 'Learn more in the '),
		link('privacy policy'),
		const TextSpan(text: '.'),
	]);
}

// Path: sentry.consent.answers
class Translations$sentry$consent$answers$en {
	Translations$sentry$consent$answers$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Yes'
	String get yes => 'Yes';

	/// en: 'No'
	String get no => 'No';

	/// en: 'Ask me later'
	String get later => 'Ask me later';
}

// Path: settings.prefDescriptions.hideFingerDrawing
class Translations$settings$prefDescriptions$hideFingerDrawing$en {
	Translations$settings$prefDescriptions$hideFingerDrawing$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Prevents accidental toggling'
	String get shown => 'Prevents accidental toggling';

	/// en: 'Finger drawing is fixed as enabled'
	String get fixedOn => 'Finger drawing is fixed as enabled';

	/// en: 'Finger drawing is fixed as disabled'
	String get fixedOff => 'Finger drawing is fixed as disabled';
}

// Path: settings.prefDescriptions.sentry
class Translations$settings$prefDescriptions$sentry$en {
	Translations$settings$prefDescriptions$sentry$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Active'
	String get active => 'Active';

	/// en: 'Inactive'
	String get inactive => 'Inactive';

	/// en: 'Active until you restart the app'
	String get activeUntilRestart => 'Active until you restart the app';

	/// en: 'Inactive until you restart the app'
	String get inactiveUntilRestart => 'Inactive until you restart the app';
}

// Path: login.ncLoginStep.loginFlow
class Translations$login$ncLoginStep$loginFlow$en {
	Translations$login$ncLoginStep$loginFlow$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Please authorize Saber to access your Nextcloud account'
	String get pleaseAuthorize => 'Please authorize Saber to access your Nextcloud account';

	/// en: 'Please follow the prompts in the Nextcloud interface'
	String get followPrompts => 'Please follow the prompts in the Nextcloud interface';

	/// en: 'Login page didn't open? Click here'
	String get browserDidntOpen => 'Login page didn\'t open? Click here';
}

// Path: login.encLoginStep.encFaq.0
class Translations$login$encLoginStep$encFaq$0$en {
	Translations$login$encLoginStep$encFaq$0$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'What is an encryption password? Why use two passwords?'
	String get q => 'What is an encryption password? Why use two passwords?';

	/// en: 'The Nextcloud password is used to access the cloud. The encryption password "scrambles" your data before it ever reaches the cloud. Even if someone gains access to your Nextcloud account, your notes will remain safe and encrypted with a separate password. This provides you a second layer of security to protect your data. No-one can access your notes on the server without your encryption password, but this also means that if you forget your encryption password, you will lose access to your data.'
	String get a => 'The Nextcloud password is used to access the cloud. The encryption password "scrambles" your data before it ever reaches the cloud.\nEven if someone gains access to your Nextcloud account, your notes will remain safe and encrypted with a separate password. This provides you a second layer of security to protect your data.\nNo-one can access your notes on the server without your encryption password, but this also means that if you forget your encryption password, you will lose access to your data.';
}

// Path: login.encLoginStep.encFaq.1
class Translations$login$encLoginStep$encFaq$1$en {
	Translations$login$encLoginStep$encFaq$1$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'I haven't set an encryption password yet. Where do I get it?'
	String get q => 'I haven\'t set an encryption password yet. Where do I get it?';

	/// en: 'Choose a new encryption password and enter it above. Saber will generate your encryption keys from this password automatically.'
	String get a => 'Choose a new encryption password and enter it above.\nSaber will generate your encryption keys from this password automatically.';
}

// Path: login.encLoginStep.encFaq.2
class Translations$login$encLoginStep$encFaq$2$en {
	Translations$login$encLoginStep$encFaq$2$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Can I use the same password as my Nextcloud account?'
	String get q => 'Can I use the same password as my Nextcloud account?';

	/// en: 'Yes, but keep in mind that it would be easier for the server administrator or someone else to access your notes if they gain access to your Nextcloud account.'
	String get a => 'Yes, but keep in mind that it would be easier for the server administrator or someone else to access your notes if they gain access to your Nextcloud account.';
}

// Path: editor.menu.boxFits
class Translations$editor$menu$boxFits$en {
	Translations$editor$menu$boxFits$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Stretch'
	String get fill => 'Stretch';

	/// en: 'Cover'
	String get cover => 'Cover';

	/// en: 'Contain'
	String get contain => 'Contain';
}

// Path: editor.menu.bgPatterns
class Translations$editor$menu$bgPatterns$en {
	Translations$editor$menu$bgPatterns$en.internal(this._root);

	final Translations _root; // ignore: unused_field

	// Translations

	/// en: 'Blank'
	String get none => 'Blank';

	/// en: 'College-ruled'
	String get college => 'College-ruled';

	/// en: 'College-ruled (Reverse)'
	String get collegeRtl => 'College-ruled (Reverse)';

	/// en: 'Lined'
	String get lined => 'Lined';

	/// en: 'Grid'
	String get grid => 'Grid';

	/// en: 'Dots'
	String get dots => 'Dots';

	/// en: 'Staffs'
	String get staffs => 'Staffs';

	/// en: 'Tablature'
	String get tablature => 'Tablature';

	/// en: 'Cornell'
	String get cornell => 'Cornell';
}
