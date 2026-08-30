///
/// Generated file. Do not edit.
///
// coverage:ignore-file
// ignore_for_file: type=lint, unused_import
// dart format off

import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:slang/generated.dart';
import 'strings.g.dart';

// Path: <root>
class TranslationsPtBr extends Translations with BaseTranslations<AppLocale, Translations> {
	/// You can call this constructor and build your own translation instance of this locale.
	/// Constructing via the enum [AppLocale.build] is preferred.
	TranslationsPtBr({Map<String, Node>? overrides, PluralResolver? cardinalResolver, PluralResolver? ordinalResolver, TranslationMetadata<AppLocale, Translations>? meta})
		: assert(overrides == null, 'Set "translation_overrides: true" in order to enable this feature.'),
		  $meta = meta ?? TranslationMetadata(
		    locale: AppLocale.ptBr,
		    overrides: overrides ?? {},
		    cardinalResolver: cardinalResolver,
		    ordinalResolver: ordinalResolver,
		  ),
		  super(cardinalResolver: cardinalResolver, ordinalResolver: ordinalResolver);

	/// Metadata for the translations of <pt-BR>.
	@override final TranslationMetadata<AppLocale, Translations> $meta;

	late final TranslationsPtBr _root = this; // ignore: unused_field

	@override 
	TranslationsPtBr $copyWith({TranslationMetadata<AppLocale, Translations>? meta}) => TranslationsPtBr(meta: meta ?? this.$meta);

	// Translations
	@override late final _Translations$common$pt_BR common = _Translations$common$pt_BR._(_root);
	@override late final _Translations$home$pt_BR home = _Translations$home$pt_BR._(_root);
	@override late final _Translations$sentry$pt_BR sentry = _Translations$sentry$pt_BR._(_root);
	@override late final _Translations$settings$pt_BR settings = _Translations$settings$pt_BR._(_root);
	@override late final _Translations$logs$pt_BR logs = _Translations$logs$pt_BR._(_root);
	@override late final _Translations$login$pt_BR login = _Translations$login$pt_BR._(_root);
	@override late final _Translations$profile$pt_BR profile = _Translations$profile$pt_BR._(_root);
	@override late final _Translations$appInfo$pt_BR appInfo = _Translations$appInfo$pt_BR._(_root);
	@override late final _Translations$update$pt_BR update = _Translations$update$pt_BR._(_root);
	@override late final _Translations$editor$pt_BR editor = _Translations$editor$pt_BR._(_root);
	@override late final _Translations$export$pt_BR export = _Translations$export$pt_BR._(_root);
	@override late final _Translations$vault$pt_BR vault = _Translations$vault$pt_BR._(_root);
	@override late final _Translations$toolbar$pt_BR toolbar = _Translations$toolbar$pt_BR._(_root);
}

// Path: common
class _Translations$common$pt_BR extends Translations$common$en {
	_Translations$common$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get delete => 'Apagar';
	@override String get done => 'Feito';
	@override String get continueBtn => 'Continuar';
	@override String get cancel => 'Cancelar';
}

// Path: home
class _Translations$home$pt_BR extends Translations$home$en {
	_Translations$home$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$home$folderColor$pt_BR folderColor = _Translations$home$folderColor$pt_BR._(_root);
	@override late final _Translations$home$sortNames$pt_BR sortNames = _Translations$home$sortNames$pt_BR._(_root);
	@override String get selectAllNotes => 'Selecionar tudo';
	@override String get deselectAllNotes => 'Desmarcar tudo';
	@override late final _Translations$home$tabs$pt_BR tabs = _Translations$home$tabs$pt_BR._(_root);
	@override late final _Translations$home$titles$pt_BR titles = _Translations$home$titles$pt_BR._(_root);
	@override late final _Translations$home$graph$pt_BR graph = _Translations$home$graph$pt_BR._(_root);
	@override late final _Translations$home$tooltips$pt_BR tooltips = _Translations$home$tooltips$pt_BR._(_root);
	@override late final _Translations$home$create$pt_BR create = _Translations$home$create$pt_BR._(_root);
	@override String get welcome => 'Bem-vindo(a) ao Saber';
	@override String get invalidFormat => 'O arquivo que você selecionou não é suportado. Por favor selecione um arquivo .sbn, .sbn2, .sba ou .pdf.';
	@override String get noFiles => 'Nenhum arquivo encontrado';
	@override String get noPreviewAvailable => 'Nenhuma visualização disponível';
	@override late final _Translations$home$fileList$pt_BR fileList = _Translations$home$fileList$pt_BR._(_root);
	@override String get createNewNote => 'Toque no botão + para criar uma nova nota';
	@override String get backFolder => 'Retornar para a pasta anterior';
	@override late final _Translations$home$newFolder$pt_BR newFolder = _Translations$home$newFolder$pt_BR._(_root);
	@override late final _Translations$home$renameNote$pt_BR renameNote = _Translations$home$renameNote$pt_BR._(_root);
	@override late final _Translations$home$moveNote$pt_BR moveNote = _Translations$home$moveNote$pt_BR._(_root);
	@override String get deleteNote => 'Apagar nota';
	@override late final _Translations$home$renameFolder$pt_BR renameFolder = _Translations$home$renameFolder$pt_BR._(_root);
	@override late final _Translations$home$deleteFolder$pt_BR deleteFolder = _Translations$home$deleteFolder$pt_BR._(_root);
	@override late final _Translations$home$moveFolder$pt_BR moveFolder = _Translations$home$moveFolder$pt_BR._(_root);
	@override String get folderColorTitle => 'Cor da pasta';
	@override String get noNotesFound => 'Nenhuma nota encontrada';
	@override String get noSubfolders => 'Nenhuma subpasta';
	@override String moveFolderTo({required Object name}) => 'Mover "${name}" para...';
	@override String get goUp => 'Subir';
	@override String get root => 'Raiz';
	@override String get properties => 'Propriedades';
	@override String get path => 'Caminho';
	@override String pathValue({required Object path}) => 'Caminho: ${path}';
	@override String get lastModified => 'Última modificação';
	@override String lastModifiedValue({required Object date}) => 'Última modificação: ${date}';
	@override String get size => 'Tamanho';
	@override String sizeValue({required Object size}) => 'Tamanho: ${size} KB';
	@override String get close => 'Fechar';
	@override String get deleteNoteConfirm => 'Tem certeza de que deseja apagar esta nota?';
	@override String get color => 'Cor';
	@override String get noNotesToGraph => 'Nenhuma nota para o gráfico';
	@override String failedToLoadGraph({required Object error}) => 'Falha ao carregar o gráfico: ${error}';
	@override String get graphTitle => 'Gráfico';
	@override String get importPdf => 'Importar PDF';
	@override String pdfFilesSelected({required Object count}) => 'Você selecionou ${count} arquivos PDF. Como deseja importá-los?';
	@override String get separateNotes => 'Notas separadas';
	@override String get mergeIntoOne => 'Mesclar em um único arquivo';
	@override String get deviceNoPdfImport => 'Este dispositivo não suporta importação de PDF.';
	@override String errorImporting({required Object error}) => 'Erro ao importar: ${error}';
	@override String filesImported({required Object count}) => '${count} arquivos importados';
}

// Path: sentry
class _Translations$sentry$pt_BR extends Translations$sentry$en {
	_Translations$sentry$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$sentry$consent$pt_BR consent = _Translations$sentry$consent$pt_BR._(_root);
}

// Path: settings
class _Translations$settings$pt_BR extends Translations$settings$en {
	_Translations$settings$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$settings$prefLabels$pt_BR prefLabels = _Translations$settings$prefLabels$pt_BR._(_root);
	@override late final _Translations$settings$prefDescriptions$pt_BR prefDescriptions = _Translations$settings$prefDescriptions$pt_BR._(_root);
	@override late final _Translations$settings$themeVariants$pt_BR themeVariants = _Translations$settings$themeVariants$pt_BR._(_root);
	@override late final _Translations$settings$prefCategories$pt_BR prefCategories = _Translations$settings$prefCategories$pt_BR._(_root);
	@override late final _Translations$settings$noteInkDefaults$pt_BR noteInkDefaults = _Translations$settings$noteInkDefaults$pt_BR._(_root);
	@override late final _Translations$settings$themeModes$pt_BR themeModes = _Translations$settings$themeModes$pt_BR._(_root);
	@override late final _Translations$settings$layoutSizes$pt_BR layoutSizes = _Translations$settings$layoutSizes$pt_BR._(_root);
	@override late final _Translations$settings$accentColorPicker$pt_BR accentColorPicker = _Translations$settings$accentColorPicker$pt_BR._(_root);
	@override String get systemLanguage => 'Automático';
	@override List<String> get axisDirections => [
		'Em cima',
		'Direita',
		'Embaixo',
		'Esquerda',
	];
	@override late final _Translations$settings$reset$pt_BR reset = _Translations$settings$reset$pt_BR._(_root);
	@override String get resyncEverything => 'Ressincronizar tudo';
	@override String get openDataDir => 'Abrir pasta do Saber';
	@override late final _Translations$settings$customDataDir$pt_BR customDataDir = _Translations$settings$customDataDir$pt_BR._(_root);
	@override String get autosaveDisabled => 'Nunca';
	@override String get shapeRecognitionDisabled => 'Nunca';
	@override String get defaultPageColor => 'Cor padrão da página';
	@override String get pageColor => 'Cor da página';
	@override String get defaultLineColor => 'Cor padrão da linha';
	@override String get lineColor => 'Cor da linha';
	@override String defaultLineHeight({required Object height}) => 'Altura padrão da linha: ${height}';
	@override String get defaultMargins => 'Margens padrão';
	@override String get defaultMarginColor => 'Cor padrão das margens';
	@override String get invertInDarkMode => 'Inverter no modo escuro';
	@override String get invertColors => 'Inverter cores';
	@override String get invertColorsSubtitle => 'Ideal para modo escuro';
	@override String selectTitle({required Object title}) => 'Selecionar ${title}';
}

// Path: logs
class _Translations$logs$pt_BR extends Translations$logs$en {
	_Translations$logs$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get logs => 'Registros';
	@override String get viewLogs => 'Ver registros';
	@override String get debuggingInfo => 'Os registros contêm informações úteis para depuração e desenvolvimento';
	@override String get noLogs => 'Nenhum registro aqui!';
	@override String get useTheApp => 'Os registros aparecerão aqui conforme você usa o aplicativo';
}

// Path: login
class _Translations$login$pt_BR extends Translations$login$en {
	_Translations$login$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Login';
	@override late final _Translations$login$form$pt_BR form = _Translations$login$form$pt_BR._(_root);
	@override TextSpan signup({required InlineSpanBuilder linkToSignup}) => TextSpan(children: [
		const TextSpan(text: 'Ainda não tem uma conta? '),
		linkToSignup('Registre-se agora'),
		const TextSpan(text: '!'),
	]);
	@override TextSpan notYou({required InlineSpanBuilder undoLogin}) => TextSpan(children: [
		const TextSpan(text: 'Não é você? '),
		undoLogin('Escolher outra conta'),
		const TextSpan(text: '.'),
	]);
	@override late final _Translations$login$status$pt_BR status = _Translations$login$status$pt_BR._(_root);
	@override late final _Translations$login$ncLoginStep$pt_BR ncLoginStep = _Translations$login$ncLoginStep$pt_BR._(_root);
	@override late final _Translations$login$encLoginStep$pt_BR encLoginStep = _Translations$login$encLoginStep$pt_BR._(_root);
}

// Path: profile
class _Translations$profile$pt_BR extends Translations$profile$en {
	_Translations$profile$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Meu perfil';
	@override String get logout => 'Sair';
	@override String quotaUsage({required Object used, required Object total, required Object percent}) => 'Você está usando ${used} de ${total} (${percent}%)';
	@override String get connectedTo => 'Conectado a';
	@override late final _Translations$profile$quickLinks$pt_BR quickLinks = _Translations$profile$quickLinks$pt_BR._(_root);
	@override String get faqTitle => 'Perguntas frequentes';
	@override List<dynamic> get faq => [
		_Translations$profile$faq$0$pt_BR._(_root),
		_Translations$profile$faq$1$pt_BR._(_root),
		_Translations$profile$faq$2$pt_BR._(_root),
		_Translations$profile$faq$3$pt_BR._(_root),
	];
}

// Path: appInfo
class _Translations$appInfo$pt_BR extends Translations$appInfo$en {
	_Translations$appInfo$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String licenseNotice({required Object buildYear}) => 'Notes  Copyright © 2025-${buildYear}  Gustavo Resende\nSaber  Copyright © 2022-${buildYear}  Adil Hanney\nEste programa vem sem absolutamente nenhuma garantia. Este é um software livre e você pode redistribuí-lo sob certas condições.';
	@override String get debug => 'DEBUG';
	@override String get sponsorButton => 'Toque aqui para me patrocinar ou comprar mais armazenamento';
	@override String get licenseButton => 'Toque aqui para ver mais informações de licença';
	@override String get privacyPolicyButton => 'Toque aqui para ver a política de privacidade';
}

// Path: update
class _Translations$update$pt_BR extends Translations$update$en {
	_Translations$update$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get updateAvailable => 'Atualização disponível';
	@override String get updateAvailableDescription => 'Uma nova versão do aplicativo está disponível:';
	@override String get update => 'Atualizar';
	@override String get downloadNotAvailableYet => 'O download ainda não está disponível para sua plataforma. Verifique novamente em breve.';
}

// Path: editor
class _Translations$editor$pt_BR extends Translations$editor$en {
	_Translations$editor$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override late final _Translations$editor$navigation$pt_BR navigation = _Translations$editor$navigation$pt_BR._(_root);
	@override late final _Translations$editor$pens$pt_BR pens = _Translations$editor$pens$pt_BR._(_root);
	@override late final _Translations$editor$selectionBar$pt_BR selectionBar = _Translations$editor$selectionBar$pt_BR._(_root);
	@override late final _Translations$editor$toolbar$pt_BR toolbar = _Translations$editor$toolbar$pt_BR._(_root);
	@override late final _Translations$editor$penOptions$pt_BR penOptions = _Translations$editor$penOptions$pt_BR._(_root);
	@override late final _Translations$editor$penSizePresets$pt_BR penSizePresets = _Translations$editor$penSizePresets$pt_BR._(_root);
	@override late final _Translations$editor$colors$pt_BR colors = _Translations$editor$colors$pt_BR._(_root);
	@override late final _Translations$editor$pdfLoading$pt_BR pdfLoading = _Translations$editor$pdfLoading$pt_BR._(_root);
	@override late final _Translations$editor$vaultPdfLargeRam$pt_BR vaultPdfLargeRam = _Translations$editor$vaultPdfLargeRam$pt_BR._(_root);
	@override late final _Translations$editor$imageOptions$pt_BR imageOptions = _Translations$editor$imageOptions$pt_BR._(_root);
	@override late final _Translations$editor$menu$pt_BR menu = _Translations$editor$menu$pt_BR._(_root);
	@override late final _Translations$editor$newerFileFormat$pt_BR newerFileFormat = _Translations$editor$newerFileFormat$pt_BR._(_root);
	@override late final _Translations$editor$quill$pt_BR quill = _Translations$editor$quill$pt_BR._(_root);
	@override late final _Translations$editor$hud$pt_BR hud = _Translations$editor$hud$pt_BR._(_root);
	@override String get pages => 'Páginas';
	@override String get untitled => 'Sem título';
	@override String get needsToSaveBeforeExiting => 'Salvando suas alterações... Você pode sair do editor com segurança quando terminar';
	@override String get plot3dSurface => 'Plotar superfície 3D';
	@override String get addInternalLink => 'Adicionar link interno';
	@override String get noNotesMatchQuery => 'Nenhuma nota corresponde à pesquisa';
	@override String get tagsAndLinks => 'Tags e links';
	@override String get noLinksOnPage => 'Nenhum link nesta página';
	@override String get strokeToText => 'Traço para texto';
	@override String get selectionToLatex => 'Seleção para LaTeX';
	@override String get noteHandwritingToLatex => 'Traços da nota para LaTeX';
	@override String get recognizedLatexTitle => 'LaTeX reconhecido';
	@override String get calculate => 'Calcular';
	@override String get lockImage => 'Bloquear imagem';
	@override String get unlockImage => 'Desbloquear imagem';
	@override String get cropImage => 'Recortar imagem';
	@override String get setAsBackground => 'Definir como fundo';
	@override String get copyToClipboard => 'Copiado para a área de transferência';
	@override String get copy => 'Copiar';
	@override String get goBack => 'Voltar';
	@override String get add => 'Adicionar';
	@override String get close => 'Fechar';
	@override String get imageSetAsBackground => 'Imagem definida como fundo';
	@override String get cropBitmapOnly => 'Recorte disponível apenas para imagens bitmap';
	@override String get failedToLoadImageForCrop => 'Falha ao carregar imagem para recorte';
	@override String failedToResolveEquation({required Object error}) => 'Falha ao resolver equação: ${error}';
	@override String get equationHint => 'Não foi possível resolver a equação. Certifique-se de incluir o sinal de igual "=".';
	@override String get couldNotRecognizeText => 'Não foi possível reconhecer o texto';
	@override String recognitionError({required Object error}) => 'Erro de reconhecimento: ${error}';
	@override String failedToDeleteNote({required Object error}) => 'Falha ao apagar nota: ${error}';
	@override String get errorImportingImage => 'Erro ao importar imagem';
	@override String errorImportingImageIndex({required Object index, required Object error}) => 'Erro ao importar imagem ${index}: ${error}';
	@override String errorInsertingImage({required Object error}) => 'Erro ao inserir imagem: ${error}';
	@override String get createTable => 'Criar tabela';
	@override String get dataAndTools => 'Dados e ferramentas';
	@override String get insert => 'Inserir';
	@override String get export => 'Exportar';
	@override String get splitView => 'Modo dividido';
	@override String get actions => 'Ações';
	@override String get invertInDarkMode => 'Inverter no modo escuro';
	@override String get overrideAppSettingForNote => 'Substituir configuração do app apenas para esta nota';
	@override String get replaceDefault => 'Substituir padrão';
	@override String get portrait => 'Retrato';
	@override String get landscape => 'Paisagem';
	@override String selectTitle({required Object title}) => 'Selecionar ${title}';
	@override String get plotFunction => 'Plotar função';
	@override String get calculator => 'Calculadora';
	@override String get insertTable => 'Inserir tabela';
	@override String get plot3D => 'Plot 3D';
	@override String get openSecondNote => 'Abrir segunda nota';
	@override String get noNotesMatchSearch => 'Nenhuma nota corresponde à pesquisa';
	@override String get pickFile => 'Escolher arquivo';
	@override String get editorTitle => 'Editor';
}

// Path: export
class _Translations$export$pt_BR extends Translations$export$en {
	_Translations$export$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get noValidPagesSelected => 'Nenhuma página válida selecionada';
	@override String exportFailed({required Object error}) => 'Falha na exportação: ${error}';
	@override String get exportNote => 'Exportar nota';
	@override String get format => 'Formato';
	@override String get pdf => 'PDF';
	@override String get png => 'PNG';
	@override String get pngSubtitle => 'Exportação rápida; codificação nativa (melhor em alta resolução)';
	@override String get jpeg => 'JPEG';
	@override String get jpegSubtitle => 'Arquivos menores; mais lento em alta resolução que PNG';
	@override String get pages => 'Páginas';
	@override String get allPages => 'Todas as páginas';
	@override String get currentPage => 'Página atual';
	@override String get customRange => 'Intervalo personalizado';
	@override String get invertColors => 'Inverter cores';
	@override String get invertColorsSubtitle => 'Exportar nota com cores de página e tinta invertidas';
	@override String get cancel => 'Cancelar';
	@override String get export => 'Exportar';
	@override String get exportSba => 'Exportar SBA';
	@override String get exportMetadata => 'Exportar metadados';
	@override String get exportMetadataSubtitle => 'Incluir datas de criação e edição, tempo gasto, local e impressão digital da página no arquivo. Desligue para compartilhar com menos dados.';
	@override String get unencrypted => 'Não criptografado';
	@override String get encrypted => 'Criptografado (definir senha)';
	@override String get setSharedPassword => 'Definir senha compartilhada';
	@override String get encryptedSba => 'SBA criptografado';
	@override String get import => 'Importar';
	@override String get exportSbaContent => 'Exporte sem criptografia (compartilhe como está) ou criptografado com uma senha que você pode compartilhar com o destinatário.\n\nLinks e tags são sempre removidos ao exportar.';
	@override String get setPasswordContent => 'Digite uma senha para criptografar o SBA. Compartilhe esta senha com o destinatário para que ele possa abrir o arquivo.';
	@override String get passwordRequired => 'Senha é obrigatória';
	@override String get passwordsDoNotMatch => 'As senhas não coincidem';
	@override String get confirmPassword => 'Confirmar senha';
	@override String get encryptedSbaContent => 'Este arquivo SBA está criptografado. Digite a senha compartilhada para importar a nota.';
	@override String get customRangeHint => 'ex: 1,3,5-7';
	@override String get pageNumbers => 'Números das páginas';
	@override String get resolution => 'Resolução';
	@override String get resolutionPdfVector => 'Traços vetoriais (leve, nítido em qualquer zoom)';
	@override String get resolution72 => '72 DPI (rápido)';
	@override String get resolution150 => '150 DPI';
	@override String get resolution300 => '300 DPI (qualidade de impressão)';
	@override String get exportFolder => 'Exportar pasta';
	@override String get exportFolderAsSba => 'Como arquivos SBA';
	@override String get exportFolderAsPdf => 'Como arquivos PDF';
	@override String get exportFolderSubtitle => 'Um arquivo por nota — sem arquivos sbn2 separados';
	@override String get preparingExport => 'Preparando exportação...';
	@override String get exportFolderEmpty => 'Nenhuma nota para exportar nesta pasta';
	@override String get shareLinks => 'Compartilhar Links';
	@override String get shareLinksSubtitle => 'Incluir páginas vinculadas na exportação para o destinatário receber um documento autocontido';
	@override String get defaultExportPath => 'Caminho padrão de exportação';
	@override String get defaultExportPathSubtitle => 'Arquivos exportados são salvos aqui. Obrigatório ao exportar com Compartilhar Links.';
	@override String get defaultExportPathRequired => 'Defina o Caminho padrão de exportação nas Configurações antes de exportar com Compartilhar Links.';
	@override String get exportingNote => 'Exportando nota...';
	@override String get exportComplete => 'Exportação concluída';
	@override String get importAfterExportDone => 'Por favor, importe após a exportação terminar.';
}

// Path: vault
class _Translations$vault$pt_BR extends Translations$vault$en {
	_Translations$vault$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unlock => 'Desbloquear';
	@override String get vaultLocked => 'Cofre bloqueado';
	@override String get vaultLockedMessage => 'Suas notas estão criptografadas. Digite sua senha para acessá-las.';
	@override String filesWaitingToImport({required Object count}) => 'Você tem ${count} arquivo(s) aguardando importação. Desbloqueie para continuar.';
	@override String get password => 'Senha';
	@override String get failedToInit => 'Falha ao inicializar o cofre. Tente novamente.';
	@override String get incorrectOrCorrupted => 'Senha incorreta ou cofre corrompido.';
	@override String migrationErrorContent({required Object error}) => 'Falha ao migrar arquivos: ${error}\n\nSeus arquivos permanecem no local original.';
	@override String get vaultCreatedContent => 'Suas notas foram criptografadas e armazenadas no cofre. Você precisará digitar sua senha ao reiniciar o aplicativo.';
	@override String get vaultDisabledContent => 'Suas notas foram descriptografadas e movidas de volta ao armazenamento regular.';
	@override String get migrationError => 'Erro de migração';
	@override String get vaultCreated => 'Cofre criado';
	@override String get incorrectPassword => 'Senha incorreta';
	@override String get incorrectPasswordMessage => 'A senha que você digitou está incorreta.';
	@override String get vaultDisabled => 'Cofre desativado';
	@override String get createVault => 'Criar cofre';
	@override String get encryptionPassword => 'Senha de criptografia';
	@override String get backupFileName => 'Nome do arquivo de backup';
	@override String get backupComplete => 'Backup concluído';
	@override String get restoreComplete => 'Restauração concluída';
	@override String get error => 'Erro';
	@override String get migratingFiles => 'Migrando arquivos';
	@override String get migratingFilesMessage => 'Por favor, aguarde enquanto os arquivos estão sendo migrados...';
	@override String get pbkdf16384 => '16384 (Padrão)';
	@override String get pbkdf32768 => '32768 (Mais forte)';
	@override String get pbkdf65536 => '65536 (Paranóico)';
	@override String get pbkdf131072 => '131072 (Extremo)';
	@override String get block1024 => '1024 bytes (Legado)';
	@override String get block4096 => '4096 bytes (Padrão)';
	@override String get block8192 => '8192 bytes';
	@override String get block65536 => '65536 bytes (Máx)';
	@override String get createVaultContent => 'Digite uma senha para criptografar suas notas.';
	@override String get confirmPassword => 'Confirmar senha';
	@override String get passwordMinLength => 'A senha deve ter pelo menos 6 caracteres';
	@override String get advancedSecurityOptions => 'Opções avançadas de segurança';
	@override String get backupVault => 'Fazer backup do cofre';
	@override String get backupData => 'Fazer backup dos dados';
	@override String get backupVaultSubtitle => 'Exportar cofre criptografado como arquivo zip';
	@override String get backupDataSubtitle => 'Exportar notas, configurações e metadados como arquivo zip';
	@override String get restoreVault => 'Restaurar cofre';
	@override String get restoreData => 'Restaurar dados';
	@override String get restoreVaultSubtitle => 'Substituir cofre por arquivo de backup';
	@override String get restoreDataSubtitle => 'Substituir notas, configurações e metadados por arquivo de backup';
	@override String get backupCompleteVault => 'Seu backup do cofre criptografado foi salvo. O cofre está agora bloqueado e deve ser desbloqueado para continuar.';
	@override String get backupCompleteData => 'Suas notas, configurações e metadados foram salvos em backup.';
	@override String get restoreCompleteData => 'Suas notas, configurações e metadados foram restaurados. O aplicativo pode precisar reiniciar para aplicar as alterações.';
	@override String get restoreCompleteVault => 'Cofre restaurado com sucesso. Desbloqueie seu cofre para acessar as notas.';
	@override String backupFailed({required Object error}) => 'Falha no backup: ${error}';
	@override String restoreFailed({required Object error}) => 'Falha na restauração: ${error}';
	@override String get restoreBackup => 'Restaurar backup';
	@override String get restoreDataConfirm => 'Isso substituirá suas notas, configurações e metadados atuais pelo conteúdo do backup. Continuar?';
	@override String get restoreVaultConfirm => 'Isso substituirá seu cofre atual pelo conteúdo do backup. Continuar?';
	@override String get fileName => 'Nome do arquivo';
}

// Path: toolbar
class _Translations$toolbar$pt_BR extends Translations$toolbar$en {
	_Translations$toolbar$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get derivative => 'Derivada';
	@override String get integral => 'Integral';
	@override String get mode2d => '2D';
	@override String get mode3d => '3D';
	@override String get calculusGraphSaved => 'Gráfico de cálculo com legenda salvo!';
	@override String get addNewSurface => 'Adicionar nova superfície';
	@override String get addNewField => 'Adicionar novo campo';
	@override String get addNewFunction => 'Adicionar nova função';
	@override String get system2d => 'Sistema 2D (x, y)';
	@override String get system3d => 'Sistema 3D (x, y, z)';
	@override String get play => 'Reproduzir';
	@override String get stop => 'Parar';
	@override String get clear => 'Limpar';
	@override String get copyValues => 'Copiar valores';
	@override String get saveImage => 'Salvar imagem';
	@override String get saveImageMetadata => 'Salvar imagem + metadados';
	@override String get start => 'Início';
	@override String get startCap => 'Tampa inicial';
	@override String get end => 'Fim';
	@override String get endCap => 'Tampa final';
	@override String get simulatePressure => 'Simular pressão';
	@override String get complete => 'Concluir';
	@override String get savePreset => 'Salvar predefinição';
	@override String get updatePreset => 'Atualizar predefinição';
	@override String get deletePreset => 'Excluir predefinição';
	@override String get fill => 'Preencher';
	@override String get mode => 'Modo';
	@override String get eraseStroke => 'Apagar traço';
	@override String get eraseArea => 'Apagar área';
	@override String get plot => 'Plotar';
	@override String get plot2dCartesian => '2D (Cartesiano)';
	@override String get plot2dPolar => '2D (Polar)';
	@override String get plot3dSurface => 'Superfície 3D (Cartesiano)';
	@override String get plot3dSpherical => 'Superfície 3D (Esférico)';
	@override String get vectorField2d => 'Campo vetorial 2D';
	@override String get vectorField3d => 'Campo vetorial 3D (fatia)';
	@override String get findRoots => 'Encontrar raízes';
	@override String get findMin => 'Encontrar mínimo';
	@override String get findMax => 'Encontrar máximo';
	@override String get showAsymptotes => 'Mostrar assíntotas';
	@override String get findSaddle => 'Encontrar ponto de sela';
	@override String get f2d => '2D f(x)';
	@override String get f3d => '3D f(x,y)';
}

// Path: home.folderColor
class _Translations$home$folderColor$pt_BR extends Translations$home$folderColor$en {
	_Translations$home$folderColor$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get changeColor => 'Alterar cor';
	@override String get chooseColor => 'Escolher cor';
	@override String get reset => 'Redefinir cor';
}

// Path: home.sortNames
class _Translations$home$sortNames$pt_BR extends Translations$home$sortNames$en {
	_Translations$home$sortNames$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sort => 'Ordenar';
	@override String get alphabetical => 'Alfabético';
	@override String get lastModified => 'Última modificação';
	@override String get sizeOnDisk => 'Tamanho em disco';
	@override String get increasing => 'Crescente';
}

// Path: home.tabs
class _Translations$home$tabs$pt_BR extends Translations$home$tabs$en {
	_Translations$home$tabs$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get search => 'Buscar';
	@override String get home => 'Início';
	@override String get browse => 'Explorar';
	@override String get whiteboard => 'Quadro branco';
	@override String get settings => 'Configurações';
}

// Path: home.titles
class _Translations$home$titles$pt_BR extends Translations$home$titles$en {
	_Translations$home$titles$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get search => 'Buscar';
	@override String get home => 'Notas recentes';
	@override String get browse => 'Navegar';
	@override String get whiteboard => 'Quadro branco';
	@override String get settings => 'Configurações';
}

// Path: home.graph
class _Translations$home$graph$pt_BR extends Translations$home$graph$en {
	_Translations$home$graph$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String showingNotes({required Object shown, required Object total}) => 'Mostrando ${shown} de ${total} notas';
	@override String get rootSearchHint => 'Pesquisar por nome ou tag para definir a raiz';
	@override String get clearRoot => 'Todas as notas';
	@override String get selectRoot => 'Selecionar raiz';
}

// Path: home.tooltips
class _Translations$home$tooltips$pt_BR extends Translations$home$tooltips$en {
	_Translations$home$tooltips$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get viewMode => 'Alternar modo de visualização';
	@override String get treeView => 'Modo árvore';
	@override String get folderView => 'Modo pastas';
	@override String get newNote => 'Nova nota';
	@override String get showUpdateDialog => 'Mostrar caixa de diálogo de atualização';
	@override String get exportNote => 'Exportar nota';
}

// Path: home.create
class _Translations$home$create$pt_BR extends Translations$home$create$en {
	_Translations$home$create$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get newNote => 'Nova nota';
	@override String get importNote => 'Importar nota';
	@override String get infiniteNote => 'Nota infinita';
}

// Path: home.fileList
class _Translations$home$fileList$pt_BR extends Translations$home$fileList$en {
	_Translations$home$fileList$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get metaSize => 'Tamanho';
	@override String get metaModified => 'Modificado';
	@override String get metaAccessed => 'Acesso';
	@override String get metaNotesInside => 'Notas na pasta';
	@override String get accessedUnavailableVault => 'Ainda não aberto no aplicativo';
}

// Path: home.newFolder
class _Translations$home$newFolder$pt_BR extends Translations$home$newFolder$en {
	_Translations$home$newFolder$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get newFolder => 'Nova pasta';
	@override String get folderName => 'Nome da pasta';
	@override String get create => 'Criar';
	@override String get folderNameEmpty => 'O nome da pasta não pode estar vazio';
	@override String get folderNameContainsSlash => 'O nome da pasta não pode conter uma barra';
	@override String get folderNameExists => 'A pasta já existe';
}

// Path: home.renameNote
class _Translations$home$renameNote$pt_BR extends Translations$home$renameNote$en {
	_Translations$home$renameNote$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get renameNote => 'Renomear nota';
	@override String get noteName => 'Nome da nota';
	@override String get rename => 'Renomear';
	@override String get noteNameEmpty => 'O nome da nota não pode estar vazio';
	@override String get noteNameContainsSlash => 'O nome da nota não pode conter uma barra';
	@override String get noteNameExists => 'Já existe uma nota com este nome';
}

// Path: home.moveNote
class _Translations$home$moveNote$pt_BR extends Translations$home$moveNote$en {
	_Translations$home$moveNote$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get moveNote => 'Mover nota';
	@override String moveNotes({required Object n}) => 'Mover ${n} notas';
	@override String moveName({required Object f}) => 'Mover ${f}';
	@override String get move => 'Mover';
	@override String renamedTo({required Object newName}) => 'A nota será renomeada para ${newName}';
	@override String get multipleRenamedTo => 'As seguintes notas serão renomeadas:';
	@override String numberRenamedTo({required Object n}) => '${n} notas serão renomeadas para evitar conflitos';
}

// Path: home.renameFolder
class _Translations$home$renameFolder$pt_BR extends Translations$home$renameFolder$en {
	_Translations$home$renameFolder$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get renameFolder => 'Renomear pasta';
	@override String get folderName => 'Nome da pasta';
	@override String get rename => 'Renomear';
	@override String get folderNameEmpty => 'O nome da pasta não pode estar vazio';
	@override String get folderNameContainsSlash => 'O nome da pasta não pode conter uma barra';
	@override String get folderNameExists => 'Já existe uma pasta com este nome';
}

// Path: home.deleteFolder
class _Translations$home$deleteFolder$pt_BR extends Translations$home$deleteFolder$en {
	_Translations$home$deleteFolder$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get deleteFolder => 'Apagar pasta';
	@override String deleteName({required Object f}) => 'Apagar ${f}';
	@override String get delete => 'Apagar';
	@override String get alsoDeleteContents => 'Apagar também todas as notas dentro desta pasta';
}

// Path: home.moveFolder
class _Translations$home$moveFolder$pt_BR extends Translations$home$moveFolder$en {
	_Translations$home$moveFolder$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get moveFolder => 'Mover pasta';
	@override String moveName({required Object f}) => 'Mover ${f}';
	@override String get move => 'Mover';
	@override String renamedTo({required Object newName}) => 'A pasta será renomeada para ${newName}';
	@override String get cantMoveHere => 'Não é possível mover a pasta para cá';
}

// Path: sentry.consent
class _Translations$sentry$consent$pt_BR extends Translations$sentry$consent$en {
	_Translations$sentry$consent$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Ajudar a melhorar o Saber?';
	@override late final _Translations$sentry$consent$description$pt_BR description = _Translations$sentry$consent$description$pt_BR._(_root);
	@override late final _Translations$sentry$consent$answers$pt_BR answers = _Translations$sentry$consent$answers$pt_BR._(_root);
}

// Path: settings.prefLabels
class _Translations$settings$prefLabels$pt_BR extends Translations$settings$prefLabels$en {
	_Translations$settings$prefLabels$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get strokeStabilization => 'Estabilização de traço';
	@override String get flatEdge => 'Borda plana';
	@override String get highlighterCapFlat => 'Plano';
	@override String get highlighterCapRound => 'Redondo';
	@override String get strokeStabilizationAmount => 'Quantidade de estabilização';
	@override String get strokePrediction => 'Predição de traço';
	@override String get strokePredictionAmount => 'Intensidade da predição';
	@override String get toolbarColorSlotsCount => 'Slots de cor na barra';
	@override String get penSizePresetCount => 'Presets de espessura da caneta';
	@override String get penSizePresetSlot => 'Preset';
	@override String get themeVariant => 'Variante do tema';
	@override String get locale => 'Idioma do aplicativo';
	@override String get appTheme => 'Tema do aplicativo';
	@override String get platform => 'Tipo do tema';
	@override String get layoutSize => 'Tipo de leiaute';
	@override String get customAccentColor => 'Cor de destaque personalizada';
	@override String get hyperlegibleFont => 'Fonte Atkinson Hyperlegible';
	@override String get shouldCheckForUpdates => 'Verificar atualizações do Saber';
	@override String get shouldAlwaysAlertForUpdates => 'Atualizações mais rápidas';
	@override String get allowInsecureConnections => 'Permitir conexões inseguras';
	@override String get editorToolbarAlignment => 'Posição da barra de ferramentas';
	@override String get editorToolbarShowInFullscreen => 'Mostrar a barra de ferramentas em tela cheia';
	@override String get editorAutoInvert => 'Inverter notas no modo escuro';
	@override String get preferGreyscale => 'Preferir cores em escala de cinza';
	@override String get maxImageSize => 'Tamanho máximo da imagem';
	@override String get autoClearWhiteboardOnExit => 'Limpar quadro branco ao sair';
	@override String get disableEraserAfterUse => 'Desativar borracha automaticamente';
	@override String get hideFingerDrawingToggle => 'Ocultar botão de desenho com dedo';
	@override String get autoDisableFingerDrawingWhenStylusDetected => 'Desativar desenho com dedo automaticamente';
	@override String get editorPromptRename => 'Perguntar nome para novas notas';
	@override String get recentColorsDontSavePresets => 'Não salvar predefinições em cores recentes';
	@override String get recentColorsLength => 'Quantas cores recentes armazenar';
	@override String get printPageIndicators => 'Imprimir indicadores de página';
	@override String get autosave => 'Salvamento automático';
	@override String get shapeRecognitionDelay => 'Atraso no reconhecimento de forma';
	@override String get autoStraightenLines => 'Endireitar linhas automaticamente';
	@override String get simplifiedHomeLayout => 'Leiaute inicial simplificado';
	@override String get customDataDir => 'Pasta personalizada do Saber';
	@override String get sentry => 'Relatório de erros';
}

// Path: settings.prefDescriptions
class _Translations$settings$prefDescriptions$pt_BR extends Translations$settings$prefDescriptions$en {
	_Translations$settings$prefDescriptions$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get strokeStabilization => 'Suaviza sua escrita à mão';
	@override String get strokePrediction => 'Mostra uma ponta de tinta ligeiramente à frente da caneta enquanto você desenha (não é salva na nota; reduz a sensação de atraso)';
	@override String get strokePredictionAmount => 'Quão longe extrapolar enquanto desenha';
	@override String get toolbarColorSlotsCount => 'Número de cores para mostrar na barra de ferramentas';
	@override String get penSizePresetCount => 'Quantidade de espessuras pré-definidas na barra do editor';
	@override String get themeVariant => 'Variante do esquema de cores';
	@override String get hyperlegibleFont => 'Aumenta a legibilidade para usuários com baixa visão';
	@override String get allowInsecureConnections => '(Não recomendado) Permitir que o Saber conecte a servidores com certificados autoassinados/não confiáveis';
	@override String get preferGreyscale => 'Para telas e-ink';
	@override String get autoClearWhiteboardOnExit => 'Limpa o quadro branco após você sair do aplicativo';
	@override String get disableEraserAfterUse => 'Volta automaticamente para a caneta após usar a borracha';
	@override String get maxImageSize => 'Imagens maiores que isso serão compactadas';
	@override late final _Translations$settings$prefDescriptions$hideFingerDrawing$pt_BR hideFingerDrawing = _Translations$settings$prefDescriptions$hideFingerDrawing$pt_BR._(_root);
	@override String get autoDisableFingerDrawingWhenStylusDetected => 'Desativa o desenho com dedo quando uma caneta é detectada';
	@override String get editorPromptRename => 'Você sempre pode renomear notas depois';
	@override String get printPageIndicators => 'Mostrar indicadores de página nas exportações';
	@override String get autosave => 'Salvar automaticamente após um pequeno atraso, ou nunca';
	@override String get shapeRecognitionDelay => 'Com que frequência atualizar a visualização da forma';
	@override String get autoStraightenLines => 'Endireita linhas longas sem precisar usar a caneta de forma';
	@override String get simplifiedHomeLayout => 'Define uma altura fixa para cada visualização de nota';
	@override String get shouldAlwaysAlertForUpdates => 'Avise-me sobre atualizações assim que estiverem disponíveis';
	@override late final _Translations$settings$prefDescriptions$sentry$pt_BR sentry = _Translations$settings$prefDescriptions$sentry$pt_BR._(_root);
}

// Path: settings.themeVariants
class _Translations$settings$themeVariants$pt_BR extends Translations$settings$themeVariants$en {
	_Translations$settings$themeVariants$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get material => 'Material';
	@override String get amoled => 'AMOLED';
}

// Path: settings.prefCategories
class _Translations$settings$prefCategories$pt_BR extends Translations$settings$prefCategories$en {
	_Translations$settings$prefCategories$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get general => 'Geral';
	@override String get writing => 'Escrita';
	@override String get editor => 'Editor';
	@override String get performance => 'Desempenho';
	@override String get advanced => 'Avançado';
}

// Path: settings.noteInkDefaults
class _Translations$settings$noteInkDefaults$pt_BR extends Translations$settings$noteInkDefaults$en {
	_Translations$settings$noteInkDefaults$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get sectionTitle => 'Padrões de nota e tinta';
	@override String get changeNoteDefaults => 'Alterar padrões da nota';
	@override String get changeNoteDefaultsSubtitle => 'Padrão, espaçamento, cores e margens para notas novas';
	@override String get changeInkDefaults => 'Alterar padrões da tinta';
	@override String get changeInkDefaultsSubtitle => 'Cores na barra, espessuras e paletas';
	@override String get noteDefaultsTitle => 'Padrões da nota';
	@override String get noteDefaultsSubtitle => 'Pré-visualização ao vivo — usada ao criar uma nota';
	@override String get inkDefaultsTitle => 'Padrões da tinta';
	@override String get inkDefaultsSubtitle => 'Paletas e cores da barra';
	@override String get activePalette => 'Paleta';
	@override String get palettePickerLabel => 'Paleta';
	@override String get savePaletteAsNew => 'Nova paleta a partir da atual';
	@override String get savePaletteAsNewShort => 'Nova paleta';
	@override String get savePaletteAsNewTitle => 'Salvar paleta';
	@override String get toolbarSlotsHint => 'Toque para alterar cada cor da barra.';
	@override String get renamePalette => 'Renomear paleta';
	@override String get renamePaletteTitle => 'Renomear paleta';
	@override String get paletteNameHint => 'Nome';
	@override String get deletePaletteConfirm => 'Remover esta paleta? As cores na barra permanecem até você escolher outra paleta.';
	@override String get toolbarSlotsDropdownLabel => 'Cores na barra';
	@override String toolbarSlotColor({required Object index}) => 'Slot de cor ${index}';
	@override String get penSizePresetCountLabel => 'Presets de espessura do traço';
}

// Path: settings.themeModes
class _Translations$settings$themeModes$pt_BR extends Translations$settings$themeModes$en {
	_Translations$settings$themeModes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get system => 'Sistema';
	@override String get light => 'Claro';
	@override String get dark => 'Escuro';
}

// Path: settings.layoutSizes
class _Translations$settings$layoutSizes$pt_BR extends Translations$settings$layoutSizes$en {
	_Translations$settings$layoutSizes$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get auto => 'Automático';
	@override String get phone => 'Celular';
	@override String get tablet => 'Tablet';
}

// Path: settings.accentColorPicker
class _Translations$settings$accentColorPicker$pt_BR extends Translations$settings$accentColorPicker$en {
	_Translations$settings$accentColorPicker$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pickAColor => 'Selecionar uma cor';
}

// Path: settings.reset
class _Translations$settings$reset$pt_BR extends Translations$settings$reset$en {
	_Translations$settings$reset$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Redefinir esta configuração?';
	@override String get button => 'Redefinir';
}

// Path: settings.customDataDir
class _Translations$settings$customDataDir$pt_BR extends Translations$settings$customDataDir$en {
	_Translations$settings$customDataDir$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get cancel => 'Cancelar';
	@override String get select => 'Selecionar';
	@override String get mustBeEmpty => 'A pasta selecionada deve estar vazia';
	@override String get mustBeDoneSyncing => 'Certifique-se de que a sincronização esteja concluída antes de alterar a pasta';
	@override String get unsupported => 'Este recurso é atualmente apenas para desenvolvedores. Usá-lo provavelmente resultará em perda de dados.';
}

// Path: login.form
class _Translations$login$form$pt_BR extends Translations$login$form$en {
	_Translations$login$form$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override TextSpan agreeToPrivacyPolicy({required InlineSpanBuilder linkToPrivacyPolicy}) => TextSpan(children: [
		const TextSpan(text: 'Ao fazer login, você concorda com a '),
		linkToPrivacyPolicy('Política de Privacidade'),
		const TextSpan(text: '.'),
	]);
}

// Path: login.status
class _Translations$login$status$pt_BR extends Translations$login$status$en {
	_Translations$login$status$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get loggedOut => 'Desconectado';
	@override String get tapToLogin => 'Toque para fazer login com o Nextcloud';
	@override String hi({required Object u}) => 'Olá, ${u}!';
	@override String get almostDone => 'Quase pronto para sincronização, toque para finalizar o login';
	@override String get loggedIn => 'Logado com o Nextcloud';
}

// Path: login.ncLoginStep
class _Translations$login$ncLoginStep$pt_BR extends Translations$login$ncLoginStep$en {
	_Translations$login$ncLoginStep$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get whereToStoreData => 'Escolha onde deseja armazenar seus dados:';
	@override String get saberNcServer => 'Servidor Nextcloud do Saber';
	@override String get otherNcServer => 'Outro servidor Nextcloud';
	@override String get serverUrl => 'URL do servidor';
	@override String get loginWithSaber => 'Login com Saber';
	@override String get loginWithNextcloud => 'Login com Nextcloud';
	@override late final _Translations$login$ncLoginStep$loginFlow$pt_BR loginFlow = _Translations$login$ncLoginStep$loginFlow$pt_BR._(_root);
}

// Path: login.encLoginStep
class _Translations$login$encLoginStep$pt_BR extends Translations$login$encLoginStep$en {
	_Translations$login$encLoginStep$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get enterEncPassword => 'Para proteger seus dados, digite sua senha de criptografia:';
	@override String get newToSaber => 'Novo no Saber? Basta digitar uma nova senha de criptografia.';
	@override String get encPassword => 'Senha de criptografia';
	@override String get encFaqTitle => 'Perguntas frequentes';
	@override String get wrongEncPassword => 'A descriptografia falhou com a senha fornecida. Por favor, tente inseri-la novamente.';
	@override String get connectionFailed => 'Algo deu errado ao conectar-se ao servidor. Por favor, tente novamente mais tarde.';
	@override List<dynamic> get encFaq => [
		_Translations$login$encLoginStep$encFaq$0$pt_BR._(_root),
		_Translations$login$encLoginStep$encFaq$1$pt_BR._(_root),
		_Translations$login$encLoginStep$encFaq$2$pt_BR._(_root),
	];
}

// Path: profile.quickLinks
class _Translations$profile$quickLinks$pt_BR extends Translations$profile$quickLinks$en {
	_Translations$profile$quickLinks$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get serverHomepage => 'Página inicial do servidor';
	@override String get deleteAccount => 'Apagar conta';
}

// Path: profile.faq.0
class _Translations$profile$faq$0$pt_BR extends Translations$profile$faq$0$en {
	_Translations$profile$faq$0$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'Eu perderei minhas notas se eu sair da minha conta?';
	@override String get a => 'Não. Suas notas permanecerão tanto no seu dispositivo quanto no servidor. Elas não serão sincronizadas com o servidor até você fazer login novamente. Certifique-se de que a sincronização esteja concluída antes de sair para não perder nenhum dado (veja o progresso da sincronização na tela inicial).';
}

// Path: profile.faq.1
class _Translations$profile$faq$1$pt_BR extends Translations$profile$faq$1$en {
	_Translations$profile$faq$1$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'Como altero minha senha do Nextcloud?';
	@override String get a => 'Vá para o site do seu servidor e faça login. Então vá para Configurações > Segurança > Mudar senha. Você precisará sair e fazer login novamente no Saber após alterar sua senha.';
}

// Path: profile.faq.2
class _Translations$profile$faq$2$pt_BR extends Translations$profile$faq$2$en {
	_Translations$profile$faq$2$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'Como altero minha senha de criptografia?';
	@override String get a => '0. Certifique-se de que a sincronização esteja concluída (veja o progresso da sincronização na tela inicial).\n1. Saia do Saber.\n2. Vá para o site do seu servidor e apague sua pasta \'Saber\'. Isso apagará todas as suas notas do servidor.\n3. Faça login novamente no Saber. Você pode escolher uma nova senha de criptografia ao fazer login.\n4. Não se esqueça de sair e fazer login novamente no Saber em seus outros dispositivos também.';
}

// Path: profile.faq.3
class _Translations$profile$faq$3$pt_BR extends Translations$profile$faq$3$en {
	_Translations$profile$faq$3$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'Como posso apagar minha conta?';
	@override String get a => 'Toque no botão "${_root.profile.quickLinks.deleteAccount}" acima e faça login se necessário.\nSe você estiver usando o servidor oficial do Saber, sua conta será apagada após um período de carência de 1 semana. Você pode entrar em contato comigo em adilhanney@disroot.org durante este período para cancelar a exclusão.\nSe você estiver usando um servidor de terceiros, pode não haver uma opção para apagar sua conta: você precisará consultar a política de privacidade do servidor para mais informações.';
}

// Path: editor.navigation
class _Translations$editor$navigation$pt_BR extends Translations$editor$navigation$en {
	_Translations$editor$navigation$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Notes';
	@override String get pdfOutlines => 'Tópicos';
	@override String get noPdfOutlineEntries => 'Sem entradas de tópicos';
	@override String get noOutlineEntriesHint => 'Adicione tópicos para marcar páginas nesta nota. Eles são incluídos ao exportar como PDF.';
	@override String get addOutlineForPage => 'Adicionar tópico para a página atual';
	@override String get renameOutline => 'Renomear tópico';
	@override String get deleteOutline => 'Excluir tópico';
	@override String get outlineTitle => 'Título';
	@override String get outlineActions => 'Ações do tópico';
	@override String get firstPage => 'Primeira página';
	@override String get lastPage => 'Última página';
	@override String get goToPage => 'Ir para página';
	@override String get pageNumber => 'Número da página';
	@override String pageNumberHint({required Object total}) => 'Página ${total}';
}

// Path: editor.pens
class _Translations$editor$pens$pt_BR extends Translations$editor$pens$en {
	_Translations$editor$pens$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get calligraphyPen => 'Caneta de caligrafia';
	@override String get fountainPen => 'Caneta tinteiro';
	@override String get ballpointPen => 'Caneta esferográfica';
	@override String get advancedPen => 'Caneta avançada';
	@override String get advancedPencil => 'Lápis avançado';
	@override String get highlighter => 'Marcador';
	@override String get shapePen => 'Caneta de forma';
	@override String get laserPointer => 'Apontador laser';
}

// Path: editor.selectionBar
class _Translations$editor$selectionBar$pt_BR extends Translations$editor$selectionBar$en {
	_Translations$editor$selectionBar$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get copy => 'Copiar';
	@override String get cut => 'Recortar';
	@override String get paste => 'Colar';
	@override String get move => 'Mover';
	@override String get delete => 'Excluir';
	@override String get duplicate => 'Duplicar';
	@override String get share => 'Compartilhar';
	@override String get shareAsSvg => 'Compartilhar como SVG';
	@override String get changeColor => 'Alterar cor';
	@override String get changeStrokeType => 'Alterar tipo de traço';
	@override String get changeStrokeTypeTitle => 'Alterar tipo de traço';
	@override String get changeStrokeTypeHint =>
			'Converter os traços selecionados para outra caneta.';
}

// Path: editor.toolbar
class _Translations$editor$toolbar$pt_BR extends Translations$editor$toolbar$en {
	_Translations$editor$toolbar$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get toggleColors => 'Alternar cores';
	@override String get select => 'Selecionar';
	@override String get toggleEraser => 'Alternar borracha';
	@override String get photo => 'Imagens';
	@override String get text => 'Texto';
	@override String get toggleFingerDrawing => 'Alternar desenho com dedo';
	@override String get undo => 'Desfazer';
	@override String get redo => 'Refazer';
	@override String get export => 'Exportar';
	@override String get exportAs => 'Exportar como:';
	@override String get fullscreen => 'Tela cheia (F11)';
	@override String get regionScreenshot => 'Captura de região';
	@override String get regionScreenshotHint => 'Arraste para selecionar uma área';
	@override String get regionScreenshotTitle => 'Compartilhar ou copiar a captura?';
	@override String get regionScreenshotBody => 'Compartilhe com outro app, ou copie a imagem para a área de transferência.';
	@override String get regionScreenshotShare => 'Compartilhar';
	@override String get regionScreenshotCopy => 'Copiar para a área de transferência';
	@override String get regionScreenshotTooSmall => 'Seleção muito pequena';
	@override String get regionScreenshotFailed => 'Falha ao capturar a tela';
}

// Path: editor.penOptions
class _Translations$editor$penOptions$pt_BR extends Translations$editor$penOptions$en {
	_Translations$editor$penOptions$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get size => 'Tamanho';
	@override String get opacity => 'Opacidade';
	@override String get thinning => 'Afinação';
	@override String get smoothing => 'Suavização';
	@override String get streamline => 'Streamline';
	@override String get pressureSensitivity => 'Sensibilidade à pressão';
	@override String get velocityThinning => 'Afinação por velocidade';
	@override String get minSizeRatio => 'Razão mín. de largura';
	@override String get maxSizeRatio => 'Razão máx. de largura';
	@override String get startTaper => 'Afinação inicial';
	@override String get endTaper => 'Afinação final';
	@override String get easing => 'Easing da largura';
	@override String get startEasing => 'Easing do início';
	@override String get endEasing => 'Easing do fim';
	@override String get neonStroke => 'Traço neon';
	@override String get presetNameHint => 'Nome do preset';
	@override String get pencilNoise => 'Grão do lápis';
	@override String get pencilNoiseHint => 'Ruído procedural rápido (sem imagens). Os padrões são otimizados para desenho fluido.';
	@override String get noiseGrainScale => 'Tamanho do grão';
	@override String get noiseThreshold => 'Cobertura';
	@override String get noiseContrast => 'Contraste';
	@override String get noiseFineMix => 'Mistura de pontilhado fino';
	@override String get resetNoiseDefaults => 'Redefinir grão';
	@override String get pressureMapsTo => 'Pressão da caneta';
	@override String get pressureToThickness => 'Espessura';
	@override String get pressureToCoverage => 'Cobertura';
	@override String get pencilShadow => 'Sombra';
}

// Path: editor.penSizePresets
class _Translations$editor$penSizePresets$pt_BR extends Translations$editor$penSizePresets$en {
	_Translations$editor$penSizePresets$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String editTitle({required Object n}) => 'Preset de caneta ${n}';
	@override String get editSubtitle => 'Ajuste dentro do editor tocando duas vezes no chip de preset quando estiver nesta nota.';
	@override String get sameAsPenSlider => 'Igual ao controle da caneta (valores como 1,0 a 10,0 nos nomes iguais ao modal da caneta).';
	@override String get tooltip => 'Toque rápido aplica espessura; toque duplo com o editor aberto permite editar o preset só desta nota.';
}

// Path: editor.colors
class _Translations$editor$colors$pt_BR extends Translations$editor$colors$en {
	_Translations$editor$colors$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get colorPicker => 'Seletor de cores';
	@override String customBrightnessHue({required Object b, required Object h}) => 'Personalizado ${b} ${h}';
	@override String customHue({required Object h}) => 'Personalizado ${h}';
	@override String get dark => 'escuro';
	@override String get light => 'claro';
	@override String get black => 'Preto';
	@override String get darkGrey => 'Cinza escuro';
	@override String get grey => 'Cinza';
	@override String get lightGrey => 'Cinza claro';
	@override String get white => 'Branco';
	@override String get red => 'Vermelho';
	@override String get green => 'Verde';
	@override String get cyan => 'Ciano';
	@override String get blue => 'Azul';
	@override String get yellow => 'Amarelo';
	@override String get purple => 'Roxo';
	@override String get pink => 'Rosa';
	@override String get orange => 'Laranja';
	@override String get pastelRed => 'Vermelho pastel';
	@override String get pastelOrange => 'Laranja pastel';
	@override String get pastelYellow => 'Amarelo pastel';
	@override String get pastelGreen => 'Verde pastel';
	@override String get pastelCyan => 'Ciano pastel';
	@override String get pastelBlue => 'Azul pastel';
	@override String get pastelPurple => 'Roxo pastel';
	@override String get pastelPink => 'Rosa pastel';
}

// Path: editor.pdfLoading
class _Translations$editor$pdfLoading$pt_BR extends Translations$editor$pdfLoading$en {
	_Translations$editor$pdfLoading$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get decrypting => 'Descriptografando PDF…';
	@override String get loading => 'Carregando PDF…';
}

// Path: editor.vaultPdfLargeRam
class _Translations$editor$vaultPdfLargeRam$pt_BR extends Translations$editor$vaultPdfLargeRam$en {
	_Translations$editor$vaultPdfLargeRam$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get allowLarge => 'Permitir PDFs grandes na RAM';
	@override String get allowLargeSubtitleOn => 'PDFs >100MB podem carregar na RAM (risco de travamento)';
	@override String get allowLargeSubtitleOff => 'PDFs >100MB sempre usam arquivo temporário (padrão, seguro)';
}

// Path: editor.imageOptions
class _Translations$editor$imageOptions$pt_BR extends Translations$editor$imageOptions$en {
	_Translations$editor$imageOptions$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get title => 'Opções de imagem';
	@override String get invertible => 'Invertível';
	@override String get download => 'Download';
	@override String get setAsBackground => 'Definir como fundo';
	@override String get removeAsBackground => 'Remover como fundo';
	@override String get delete => 'Excluir';
}

// Path: editor.menu
class _Translations$editor$menu$pt_BR extends Translations$editor$menu$en {
	_Translations$editor$menu$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get setCoverImage => 'Definir imagem de capa';
	@override String clearPage({required Object page, required Object totalPages}) => 'Limpar página ${page}/${totalPages}';
	@override String get clearAllPages => 'Limpar todas as páginas';
	@override String get insertPage => 'Inserir página abaixo';
	@override String get duplicatePage => 'Duplicar página';
	@override String get deletePage => 'Apagar página';
	@override String get lineHeight => 'Altura da linha';
	@override String get lineHeightDescription => 'Também controla o tamanho do texto para notas digitadas';
	@override String get lineThickness => 'Espessura da linha';
	@override String get lineThicknessDescription => 'Espessura da linha de fundo';
	@override String get backgroundImageFit => 'Ajuste da imagem de fundo';
	@override String get backgroundPattern => 'Padrão de fundo';
	@override String get import => 'Importar';
	@override String get watchServer => 'Observar atualizações no servidor';
	@override String get watchServerReadOnly => 'A edição está desativada enquanto observa o servidor';
	@override late final _Translations$editor$menu$boxFits$pt_BR boxFits = _Translations$editor$menu$boxFits$pt_BR._(_root);
	@override late final _Translations$editor$menu$bgPatterns$pt_BR bgPatterns = _Translations$editor$menu$bgPatterns$pt_BR._(_root);
}

// Path: editor.newerFileFormat
class _Translations$editor$newerFileFormat$pt_BR extends Translations$editor$newerFileFormat$en {
	_Translations$editor$newerFileFormat$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get readOnlyMode => 'Modo somente leitura';
	@override String get title => 'Esta nota foi editada usando uma versão mais recente do Saber';
	@override String get subtitle => 'A edição desta nota pode resultar na perda de algumas informações. Deseja ignorar isso e editá-la mesmo assim?';
	@override String get allowEditing => 'Permitir edição';
}

// Path: editor.quill
class _Translations$editor$quill$pt_BR extends Translations$editor$quill$en {
	_Translations$editor$quill$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get typeSomething => 'Digite algo aqui...';
}

// Path: editor.hud
class _Translations$editor$hud$pt_BR extends Translations$editor$hud$en {
	_Translations$editor$hud$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get unlockZoom => 'Desbloquear zoom';
	@override String get lockZoom => 'Bloquear zoom';
	@override String get unlockSingleFingerPan => 'Ativar rolagem com um dedo';
	@override String get lockSingleFingerPan => 'Desativar rolagem com um dedo';
	@override String get unlockAxisAlignedPan => 'Desbloquear rolagem horizontal ou vertical';
	@override String get lockAxisAlignedPan => 'Bloquear rolagem horizontal ou vertical';
}

// Path: sentry.consent.description
class _Translations$sentry$consent$description$pt_BR extends Translations$sentry$consent$description$en {
	_Translations$sentry$consent$description$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get question => 'Você gostaria de relatar automaticamente erros inesperados? Isso me ajuda a identificar e corrigir problemas mais rapidamente.';
	@override String get scope => 'Os relatórios podem conter informações sobre o erro e seu dispositivo. Fiz todos os esforços para filtrar dados pessoais, mas alguns podem permanecer.';
	@override String get currentlyOff => 'Se você conceder consentimento, o relatório de erros será ativado após reiniciar o aplicativo.';
	@override String get currentlyOn => 'Se você revogar o consentimento, reinicie o aplicativo para desativar os relatórios de erros.';
	@override TextSpan learnMoreInPrivacyPolicy({required InlineSpanBuilder link}) => TextSpan(children: [
		const TextSpan(text: 'Saiba mais na '),
		link('Política de Privacidade'),
		const TextSpan(text: '.'),
	]);
}

// Path: sentry.consent.answers
class _Translations$sentry$consent$answers$pt_BR extends Translations$sentry$consent$answers$en {
	_Translations$sentry$consent$answers$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get yes => 'Sim';
	@override String get no => 'Não';
	@override String get later => 'Pergunte-me mais tarde';
}

// Path: settings.prefDescriptions.hideFingerDrawing
class _Translations$settings$prefDescriptions$hideFingerDrawing$pt_BR extends Translations$settings$prefDescriptions$hideFingerDrawing$en {
	_Translations$settings$prefDescriptions$hideFingerDrawing$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get shown => 'Previne alternância acidental';
	@override String get fixedOn => 'O desenho com o dedo está fixo como ativado';
	@override String get fixedOff => 'O desenho com o dedo está fixo como desativado';
}

// Path: settings.prefDescriptions.sentry
class _Translations$settings$prefDescriptions$sentry$pt_BR extends Translations$settings$prefDescriptions$sentry$en {
	_Translations$settings$prefDescriptions$sentry$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get active => 'Ativo';
	@override String get inactive => 'Inativo';
	@override String get activeUntilRestart => 'Ativo até você reiniciar o aplicativo';
	@override String get inactiveUntilRestart => 'Inativo até você reiniciar o aplicativo';
}

// Path: login.ncLoginStep.loginFlow
class _Translations$login$ncLoginStep$loginFlow$pt_BR extends Translations$login$ncLoginStep$loginFlow$en {
	_Translations$login$ncLoginStep$loginFlow$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get pleaseAuthorize => 'Por favor, autorize o Saber a acessar sua conta Nextcloud';
	@override String get followPrompts => 'Por favor, siga as instruções na interface do Nextcloud';
	@override String get browserDidntOpen => 'A página de login não abriu? Clique aqui';
}

// Path: login.encLoginStep.encFaq.0
class _Translations$login$encLoginStep$encFaq$0$pt_BR extends Translations$login$encLoginStep$encFaq$0$en {
	_Translations$login$encLoginStep$encFaq$0$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'O que é uma senha de criptografia? Por que usar duas senhas?';
	@override String get a => 'A senha do Nextcloud é usada para acessar a nuvem. A senha de criptografia "embaralha" seus dados antes que eles cheguem à nuvem.\nMesmo que alguém obtenha acesso à sua conta do Nextcloud, suas notas permanecerão seguras e criptografadas com uma senha separada. Isso fornece uma segunda camada de segurança para proteger seus dados.\nNinguém pode acessar suas notas no servidor sem sua senha de criptografia, mas isso também significa que se você esquecer sua senha de criptografia, perderá o acesso aos seus dados.';
}

// Path: login.encLoginStep.encFaq.1
class _Translations$login$encLoginStep$encFaq$1$pt_BR extends Translations$login$encLoginStep$encFaq$1$en {
	_Translations$login$encLoginStep$encFaq$1$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'Ainda não defini uma senha de criptografia. Onde consigo uma?';
	@override String get a => 'Escolha uma nova senha de criptografia e digite-a acima.\nO Saber gerará suas chaves de criptografia a partir desta senha automaticamente.';
}

// Path: login.encLoginStep.encFaq.2
class _Translations$login$encLoginStep$encFaq$2$pt_BR extends Translations$login$encLoginStep$encFaq$2$en {
	_Translations$login$encLoginStep$encFaq$2$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get q => 'Posso usar a mesma senha da minha conta Nextcloud?';
	@override String get a => 'Sim, mas tenha em mente que seria mais fácil para o administrador do servidor ou outra pessoa acessar suas notas se eles obtiverem acesso à sua conta Nextcloud.';
}

// Path: editor.menu.boxFits
class _Translations$editor$menu$boxFits$pt_BR extends Translations$editor$menu$boxFits$en {
	_Translations$editor$menu$boxFits$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get fill => 'Esticar';
	@override String get cover => 'Cobrir';
	@override String get contain => 'Conter';
}

// Path: editor.menu.bgPatterns
class _Translations$editor$menu$bgPatterns$pt_BR extends Translations$editor$menu$bgPatterns$en {
	_Translations$editor$menu$bgPatterns$pt_BR._(TranslationsPtBr root) : this._root = root, super.internal(root);

	final TranslationsPtBr _root; // ignore: unused_field

	// Translations
	@override String get none => 'Em branco';
	@override String get college => 'Pautado com margem';
	@override String get collegeRtl => 'Pautado com margem (Invertido)';
	@override String get lined => 'Pautado';
	@override String get grid => 'Grade';
	@override String get dots => 'Pontos';
	@override String get staffs => 'Pentagrama';
	@override String get tablature => 'Tablatura';
	@override String get cornell => 'Cornell';
}
