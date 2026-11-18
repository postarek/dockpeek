# DockPeek

Substituto do HyperDock para Macs com Apple Silicon: ao passar o mouse sobre um ícone do Dock,
mostra miniaturas das janelas daquele app. Clique numa miniatura para trazer a janela para frente
(desminimiza se preciso); passe o mouse e clique no "x" para fechá-la.

## Como funciona

- **Hover no Dock** — observa a notificação de Acessibilidade `AXSelectedChildrenChanged` da lista do
  Dock (o Dock "seleciona" o ícone que está sob o mouse).
- **Janelas e miniaturas** — `ScreenCaptureKit` (lista as janelas do app e captura cada uma, inclusive
  as que estão cobertas por outras).
- **Foco / fechar** — API de Acessibilidade (`AXRaise`, `AXMinimized`, botão de fechar da janela).
- Funciona com o Dock embaixo, à esquerda ou à direita, e em múltiplos monitores.

## Compilar e instalar

Requer só as Command Line Tools (Swift 5.10+), macOS 14+, Mac com Apple Silicon.

```bash
./build.sh --install
```

Na primeira execução, uma janela "Set up DockPeek" conduz as duas permissões: o app já se coloca na lista
e abre a página certa do Ajustes do Sistema — **Acessibilidade** e depois **Gravação de Tela e Áudio do
Sistema** —, e a pessoa só liga a chave. Ele avança sozinho de uma para a outra e oferece reabrir o app no
fim (a Gravação de Tela só vale num processo novo). O macOS não permite que um app conceda isso sozinho.

O ícone na barra de menus mostra o estado das permissões. Na primeira execução o app se registra para
abrir no login (desligável em "Open at Login").

A assinatura ad-hoc fixa o requisito no identificador `local.dockpeek`, então recompilar não faz o macOS
esquecer as permissões.

## Ajustes no System Settings

O painel `DockPeek.prefPane` vai dentro do app (`Contents/Resources`). Ao abrir, o app o copia para
`~/Library/PreferencePanes` quando falta ou quando o build mudou — assim o painel se atualiza junto com o
app. O DockPeek aparece no fim da barra lateral do Ajustes do Sistema, e o item "Settings…" do menu abre
direto nele. O painel grava no domínio de preferências do app (`local.dockpeek`) e avisa o app por
notificação distribuída, então as mudanças valem na hora.

> Painéis `.prefPane` são um mecanismo legado da Apple — ainda funciona (é o que o HyperDock usa), mas pode
> ser removido numa versão futura do macOS.

## Atualizações

O app se atualiza sozinho a partir das releases do GitHub (`postarek/dockpeek`, público). Ele verifica
15 s depois de abrir e a cada 12 h (desligável em System Settings › DockPeek), e também pelo menu
"Check for Updates…". Ao achar versão nova, mostra as notas da versão e, com um clique, baixa o
`DockPeek-<versão>.zip`, confere identificador e assinatura, troca o app no lugar e reabre. As permissões
e os ajustes continuam. Se o app foi instalado pelo `.pkg` 1.0.x (dono root), o macOS pede a senha de
administrador uma vez; a partir do `.pkg` 1.1.0 o app já fica no nome do usuário.

Para publicar uma versão nova:

```bash
./build.sh --bump            # nova versão de teste "a" (ex.: 1.2.5 → 1.2.6a); ou --bump minor / major
./build.sh --install         # instala localmente para testar
./build.sh --bump test       # próxima versão de teste (1.2.6a → 1.2.6b), a cada rodada de ajustes
# quando aprovada:
./build.sh --bump final      # tira a letra (1.2.6b → 1.2.6)
# anote a mudança no CHANGELOG.md (em inglês: vira a nota que aparece no app)
git commit -am "DockPeek x.y.z"
./build.sh --release         # gera .pkg + .zip, faz push e cria a release no GitHub
```

Versões com letra são de teste: aparecem assim no menu e no painel, e o `--release` se recusa a publicá-las.

Na sua própria máquina, `./build.sh --install` continua instalando direto o que está no código.

## Compartilhar (instalador)

```bash
./build.sh --package
```

Gera `dist/DockPeek-<versão>.pkg` (versão no arquivo `VERSION`). Antes de gerar uma versão nova para
distribuir, suba o número com `./build.sh --bump` (`patch` por padrão; `minor` ou `major` quando couber) e
anote a mudança no `CHANGELOG.md`. O número de build (data e hora) muda sozinho a cada compilação. O instalador coloca o app em
`/Applications`, abre o DockPeek para o usuário logado (que instala o painel e pede as permissões) e
mostra no final como conceder as permissões. Só instala em Apple Silicon com macOS 14+.

**Sem conta de desenvolvedor Apple** o `.pkg` sai sem assinatura, e quem baixar verá "não é possível
verificar o desenvolvedor". Para instalar mesmo assim:

1. Dê dois cliques no `.pkg` e feche o aviso.
2. Em **Ajustes do Sistema › Privacidade e Segurança**, role até "DockPeek-x.pkg foi bloqueado" e clique em
   **Abrir Mesmo Assim**.
3. Siga o instalador normalmente.

**Com conta de desenvolvedor** (US$ 99/ano), o pacote abre sem aviso:

```bash
xcrun notarytool store-credentials dockpeek   # uma vez: Apple ID + senha de app + Team ID
DEVELOPER_ID_APP="Developer ID Application: Nome (TEAMID)" \
DEVELOPER_ID_INSTALLER="Developer ID Installer: Nome (TEAMID)" \
NOTARY_PROFILE=dockpeek ./build.sh --package
```

## Limitações conhecidas

- Janelas minimizadas aparecem com o ícone do app no lugar da miniatura (o macOS não renderiza o
  conteúdo delas).
- Janelas em outros Espaços aparecem na lista, mas o foco ativa o app em vez de levar diretamente
  àquela janela.
