# `i18n/pt_BR.i18n.yaml`

YAML under `lib/i18n/` defines translation strings or metadata for localization. Inline `#` comments in the YAML (if any) describe translator context; prefer editing the `.yaml` sources and regenerating Dart bindings with `dart run slang`.

## File role

- `_missing_translations.yaml` / `_unused_translations.yaml`: slang maintenance lists.
- `*.i18n.yaml`: locale string trees consumed by slang.

## Contents overview

```yaml
common:
  delete: Apagar
  done: Feito
  continueBtn: Continuar
  cancel: Cancelar
home:
  folderColor:
    changeColor: Alterar cor
    chooseColor: Escolher cor
    reset: Redefinir cor
  sortNames:
    sort: Ordenar
    alphabetical: Alfabético
    lastModified: Última modificação
    sizeOnDisk: Tamanho em disco
    increasing: Crescente
  selectAllNotes: Selecionar tudo
  deselectAllNotes: Desmarcar tudo
  tabs:
    search: Buscar
    home: Início
    browse: Explorar
    whiteboard: Quadro branco
    settings: Configurações
  titles:
    search: Buscar
    home: Notas recentes
    browse: Navegar
    whiteboard: Quadro branco
    settings: Configurações
  graph:
    showingNotes: Mostrando $shown de $total notas
    rootSearchHint: Pesquisar por nome ou tag para definir a raiz
    clearRoot: Todas as notas
    selectRoot: Selecionar raiz
  tooltips:
    viewMode: Alternar modo de visualização
    treeView: Modo árvore
    folderView: Modo pastas
    newNote: Nova nota
    showUpdateDialog: Mostrar caixa de diálogo de atualização
    exportNote: Exportar nota
  create:
    newNote: Nova nota
    importNote: Importar nota
    infiniteNote: Nota infinita
  welcome: Bem-vindo(a) ao Saber
  invalidFormat: O arquivo que você selecionou não é suportado. Por favor selecione um arquivo .sbn, .sbn2, .sba ou .pdf.
  noFiles: Nenhum arquivo encontrado
  noPreviewAvailable: Nenhuma visualização disponível
  createNewNote: Toque no botão + para criar uma nova nota
  backFolder: Retornar para a pasta anterior
  newFolder:
    newFolder: Nova pasta
    folderName: Nome da pasta
    create: Criar
    folderNameEmpty: O nome da pasta não pode estar vazio
    folderNameContainsSlash: O nome da pasta não pode conter uma barra
    folderNameExists: A pasta já existe
  renameNote:
    renameNote: Renomear nota
    noteName: Nome da nota
    rename: Renomear
    noteNameEmpty: O nome da nota não pode estar vazio
    noteNameContainsSlash: O nome da nota não pode conter uma barra
    noteNameExists: Já existe uma nota com este nome
  moveNote:
    moveNote: Mover nota
    moveNotes: Mover $n notas
    moveName: Mover $f
    move: Mover
    renamedTo: A nota será renomeada para $newName
    multipleRenamedTo: "As seguintes notas serão renomeadas:"
    numberRenamedTo: $n notas serão renomeadas para evitar conflitos
  deleteNote: Apagar nota
  renameFolder:
    renameFolder: Renomear pasta
    folderName: Nome da pasta
    rename: Renomear
    folderNameEmpty: O nome da pasta não pode estar vazio
    folderNameContainsSlash: O nome da pasta não pode conter uma barra
    folderNameExists: Já existe uma pasta com este nome
  deleteFolder:
    deleteFolder: Apagar pasta
    deleteName: Apagar $f
    delete: Apagar
    alsoDeleteContents: Apagar também todas as notas dentro desta pasta
  moveFolder:
    moveFolder: Mover pasta
    moveName: Mover $f
    move: Mover
    renamedTo: A pasta será renomeada para $newName
    cantMoveHere: Não é possível mover a pasta para cá
  folderColorTitle: Cor da pasta
  noNotesFound: Nenhuma nota encontrada
  noSubfolders: Nenhuma subpasta
  moveFolderTo: Mover "$name" para...
  goUp: Subir
  root: Raiz
  properties: Propriedades
  path: Caminho
  pathValue: "Caminho: $path"
  lastModified: Última modificação
  lastModifiedValue: "Última modificação: $date"
  size: Tamanho
  sizeValue: "Tamanho: $size KB"
  close: Fechar
  deleteNoteConfirm: Tem certeza de que deseja apagar esta nota?
  color: Cor
  noNotesToGraph: Nenhuma nota para o gráfico
  failedToLoadGraph: "Falha ao carregar o gráfico: $error"
  graphTitle: Gráfico
  importPdf: Importar PDF
  pdfFilesSelected: "Você selecionou $count arquivos PDF. Como deseja importá-los?"
  separateNotes: Notas separadas
  mergeIntoOne: Mesclar em um único arquivo
  deviceNoPdfImport: Este dispositivo não suporta importação de PDF.
  errorImporting: "Erro ao importar: $error"
  filesImported: $count arquivos importados
sentry:
  consent:
    title: Ajudar a melhorar o Saber?
    description:
      question: Você gostaria de relatar automaticamente erros inesperados? Isso me ajuda a identificar e corrigir problemas mais rapidamente.
      scope: Os relatórios podem conter informações sobre o erro e seu dispositivo. Fiz todos os esforços para filtrar dados pessoais, mas alguns podem permanecer.
      currentlyOff: Se você conceder consentimento, o relatório de erros será ativado após reiniciar o aplicativo.
      currentlyOn: Se você revogar o consentimento, reinicie o aplicativo para desativar os relatórios de erros.
      learnMoreInPrivacyPolicy(rich): Saiba mais na ${link(Política de Privacidade)}.
    answers:
      yes: Sim
      no: Não
      later: Pergunte-me mais tarde
settings:
  prefLabels:
    strokeStabilization: Estabilização de traço
    flatEdge: Borda plana
    highlighterCapFlat: Plano
    highlighterCapRound: Redondo
    strokeStabilizationAmount: Quantidade de estabilização
    strokePrediction: Predição de traço
    strokePredictionAmount: Intensidade da predição
    toolbarColorSlotsCount: Slots de cor na barra
    themeVariant: Variante do tema
    locale: Idioma do aplicativo
    appTheme: Tema do aplicativo
    platform: Tipo do tema
    layoutSize: Tipo de leiaute
    customAccentColor: Cor de destaque personalizada
    hyperlegibleFont: Fonte Atkinson Hyperlegible
    shouldCheckForUpdates: Verificar atualizações do Saber
    shouldAlwaysAlertForUpdates: Atualizações mais rápidas
    allowInsecureConnections: Permitir conexões inseguras
    editorToolbarAlignment: Posição da barra de ferramentas
    editorToolbarShowInFullscreen: Mostrar a barra de ferramentas em tela cheia
    editorAutoInvert: Inverter notas no modo escuro
    preferGreyscale: Preferir cores em escala de cinza
    maxImageSize: Tamanho máximo da imagem
    autoClearWhiteboardOnExit: Limpar quadro branco ao sair
    disableEraserAfterUse: Desativar borracha automaticamente
    hideFingerDrawingToggle: Ocultar botão de desenho com dedo
    autoDisableFingerDrawingWhenStylusDetected: Desativar desenho com dedo automaticamente
    editorPromptRename: Perguntar nome para novas notas
    recentColorsDontSavePresets: Não salvar predefinições em cores recentes
    recentColorsLength: Quantas cores recentes armazenar
    printPageIndicators: Imprimir indicadores de página
    autosave: Salvamento automático
    shapeRecognitionDelay: Atraso no reconhecimento de forma
    autoStraightenLines: Endireitar linhas automaticamente
    simplifiedHomeLayout: Leiaute inicial simplificado
    customDataDir: Pasta personalizada do Saber
    sentry: Relatório de erros
  prefDescriptions:
    strokeStabilization: Suaviza sua escrita à mão
    strokePrediction: Mostra uma ponta de tinta ligeiramente à frente da caneta enquanto você desenha (não é salva na nota; reduz a sensação de atraso)
    strokePredictionAmount: Quão longe extrapolar enquanto desenha
    toolbarColorSlotsCount: Número de cores para mostrar na barra de ferramentas
    themeVariant: Variante do esquema de cores
    hyperlegibleFont: Aumenta a legibilidade para usuários com baixa visão
    allowInsecureConnections: (Não recomendado) Permitir que o Saber conecte a servidores com certificados autoassinados/não confiáveis
    preferGreyscale: Para telas e-ink
    autoClearWhiteboardOnExit: Limpa o quadro branco após você sair do aplicativo
    disableEraserAfterUse: Volta automaticamente para a caneta após usar a borracha
    maxImageSize: Imagens maiores que isso serão compactadas
    hideFingerDrawing:
      shown: Previne alternância acidental
      fixedOn: O desenho com o dedo está fixo como ativado
      fixedOff: O desenho com o dedo está fixo como desativado
    autoDisableFingerDrawingWhenStylusDetected: Desativa o desenho com dedo quando uma caneta é detectada
    editorPromptRename: Você sempre pode renomear notas depois
    printPageIndicators: Mostrar indicadores de página nas exportações
    autosave: Salvar automaticamente após um pequeno atraso, ou nunca
    shapeRecognitionDelay: Com que frequência atualizar a visualização da forma
    autoStraightenLines: Endireita linhas longas sem precisar usar a caneta de forma
    simplifiedHomeLayout: Define uma altura fixa para cada visualização de nota
    shouldAlwaysAlertForUpdates: Avise-me sobre atualizações assim que estiverem disponíveis
    sentry:
      active: Ativo
      inactive: Inativo
      activeUntilRestart: Ativo até você reiniciar o aplicativo
      inactiveUntilRestart: Inativo até você reiniciar o aplicativo
  themeVariants:
    material: Material
    amoled: AMOLED
  prefCategories:
    general: Geral
    writing: Escrita
    editor: Editor
    performance: Desempenho
    advanced: Avançado
  themeModes:
    system: Sistema
    light: Claro
    dark: Escuro
  layoutSizes:
    auto: Automático
    phone: Celular
    tablet: Tablet
  accentColorPicker:
    pickAColor: Selecionar uma cor
  systemLanguage: Automático
  axisDirections:
    - Em cima
    - Direita
    - Embaixo
    - Esquerda
  reset:
    title: Redefinir esta configuração?
    button: Redefinir
  resyncEverything: Ressincronizar tudo
  openDataDir: Abrir pasta do Saber
  customDataDir:
    cancel: Cancelar
    select: Selecionar
    mustBeEmpty: A pasta selecionada deve estar vazia
    mustBeDoneSyncing: Certifique-se de que a sincronização esteja concluída antes de alterar a pasta
    unsupported: Este recurso é atualmente apenas para desenvolvedores. Usá-lo provavelmente resultará em perda de dados.
  autosaveDisabled: Nunca
  shapeRecognitionDisabled: Nunca
  defaultPageColor: Cor padrão da página
  pageColor: Cor da página
  defaultLineColor: Cor padrão da linha
  lineColor: Cor da linha
  defaultLineHeight: "Altura padrão da linha: $height"
  defaultMargins: Margens padrão
  defaultMarginColor: Cor padrão das margens
  invertInDarkMode: Inverter no modo escuro
  invertColors: Inverter cores
  invertColorsSubtitle: Ideal para modo escuro
  selectTitle: Selecionar $title
logs:
  logs: Registros
  viewLogs: Ver registros
  debuggingInfo: Os registros contêm informações úteis para depuração e desenvolvimento
  noLogs: Nenhum registro aqui!
  useTheApp: Os registros aparecerão aqui conforme você usa o aplicativo
login:
  title: Login
  form:
    agreeToPrivacyPolicy(rich): Ao fazer login, você concorda com a ${linkToPrivacyPolicy(Política de Privacidade)}.
  signup(rich): Ainda não tem uma conta? ${linkToSignup(Registre-se agora)}!
  notYou(rich): Não é você? ${undoLogin(Escolher outra conta)}.
  status:
    loggedOut: Desconectado
    tapToLogin: Toque para fazer login com o Nextcloud
    hi: Olá, $u!
    almostDone: Quase pronto para sincronização, toque para finalizar o login
    loggedIn: Logado com o Nextcloud
  ncLoginStep:
    whereToStoreData: "Escolha onde deseja armazenar seus dados:"
    saberNcServer: Servidor Nextcloud do Saber
    otherNcServer: Outro servidor Nextcloud
    serverUrl: URL do servidor
    loginWithSaber: Login com Saber
    loginWithNextcloud: Login com Nextcloud
    loginFlow:
      pleaseAuthorize: Por favor, autorize o Saber a acessar sua conta Nextcloud
      followPrompts: Por favor, siga as instruções na interface do Nextcloud
      browserDidntOpen: A página de login não abriu? Clique aqui
  encLoginStep:
    enterEncPassword: "Para proteger seus dados, digite sua senha de criptografia:"
    newToSaber: Novo no Saber? Basta digitar uma nova senha de criptografia.
    encPassword: Senha de criptografia
    encFaqTitle: Perguntas frequentes
    wrongEncPassword: A descriptografia falhou com a senha fornecida. Por favor, tente inseri-la novamente.
    connectionFailed: Algo deu errado ao conectar-se ao servidor. Por favor, tente novamente mais tarde.
    encFaq:
      -
        q: O que é uma senha de criptografia? Por que usar duas senhas?
        a: |-
          A senha do Nextcloud é usada para acessar a nuvem. A senha de criptografia "embaralha" seus dados antes que eles cheguem à nuvem.
          Mesmo 

… (truncated in docs preview)

```
