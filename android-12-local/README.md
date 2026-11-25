# Android 12 Local

Ambiente Windows x64 para instalar, executar e depurar APKs no Android 12 (API 31, x86_64). O Android Emulator, o ADB, o painel e o armazenamento do AVD rodam no computador. A instalação baixa ferramentas e imagem oficiais. A rede virtual do emulador usa a conexão do Windows.

O projeto usa a imagem Google Play de produção, com os aplicativos de fábrica da imagem. A inicialização mantém SELinux, o sandbox de aplicativos e os controles de permissões. O script de teste verifica que o shell ADB tem UID 2000 e que SELinux está em modo Enforcing.

## Preparar o Windows

1. Abra o PowerShell 7.2+ nesta pasta. Execute `.\Android.ps1 Inspect` para ver CPU, memória, disco, SDK e ferramentas disponíveis.
2. Em AMD, habilite SVM/AMD-V no UEFI se a virtualização estiver desabilitada. Em Intel, o equivalente é VT-x. O emulador também precisa de tradução de segundo nível (AMD RVI ou Intel EPT).
3. Habilite **Plataforma do Hipervisor do Windows** nos recursos opcionais do Windows. A operação equivalente é `.\Android.ps1 EnableWHPX` em PowerShell elevado. Reinicie se o Windows solicitar.
4. Execute `.\Android.ps1 Setup` e leia os termos exibidos pelo SDK Manager. O script reutiliza o SDK e um Java compatível quando encontrados. Se faltar Java, tenta instalar Microsoft OpenJDK 21 via WinGet. Também é possível apontar `JAVA_HOME` para um JDK 21 já disponível.
5. Execute `.\Android.ps1 Virtualization`. O resultado de `emulator -accel-check` deve ser `0` e identificar um hipervisor utilizável.

O padrão usa até metade dos processadores lógicos, limitado a quatro vCPUs, e aproximadamente um quarto da memória detectada, entre 1,5 e 4 GiB. O emulador escolhe a GPU inicialmente. Recomenda-se pelo menos 20 GiB livres quando SDK e AVD compartilham o mesmo volume, com espaço adicional para snapshots e APKs.

Aplique somente uma configuração de ambiente por sessão. `ANDROID12_LOCAL_HOME` permite definir uma pasta de estado absoluta. Na ausência dessa variável, o estado vai para `.local` ao lado dos scripts e o SDK local fica em `.localsdk` caso o script não encontre um SDK existente. O SDK é procurado em `ANDROID_HOME`, `ANDROID_SDK_ROOT` e no local padrão do Android Studio.

## Painel e comandos

Abra o painel com `pwsh -STA -File .\Painel.ps1`. Use **Iniciar**, **Parar**, **Reiniciar**, **Instalar APK**, **Logs**, **Diagnóstico** e **Consumo**. **Salvar recursos** aplica os novos valores na próxima inicialização.

| Ação | Exemplo PowerShell |
|---|---|
| Iniciar com janela | `.\Android.ps1 Start` |
| Encerrar com sincronização do armazenamento | `.\Android.ps1 Stop` |
| Reiniciar | `.\Android.ps1 Restart` |
| Instalar ou atualizar APK | `.\Android.ps1 Install -Apk 'C:APKsMeu app.apk'` |
| Desinstalar app de usuário | `.\Android.ps1 Uninstall -Package com.exemplo.app` |
| Medir recursos | `.\Android.ps1 Resources` |
| Ajustar recursos | `.\Android.ps1 Configure -Cores 4 -RamMB 3840 -Gpu auto` |
| Consultar logcat | `.\Android.ps1 Logs` |
| Consultar host, ADB e logs do emulador | `.\Android.ps1 Diagnose` |
| Copiar para o Android | `.\Android.ps1 Push -LocalPath .arquivo.txt -DevicePath /sdcard/Download/arquivo.txt` |
| Copiar do Android | `.\Android.ps1 Pull -DevicePath /sdcard/Download/arquivo.txt -LocalPath .arquivo.txt` |
| Salvar snapshot com Android ligado | `.\Android.ps1 Backup -Snapshot antes_do_teste` |
| Restaurar snapshot com Android ligado | `.\Android.ps1 Restore -Snapshot antes_do_teste -ConfirmRestore` |

Use o serial exibido pelo comando Start com `adb -s SERIAL` ou selecione o AVD no Android Studio. Apps de depuração próprios podem usar o depurador do Android Studio. Binários nativos do APK precisam ser compatíveis com as ABIs que a imagem oferece. Consulte `adb -s SERIAL shell getprop ro.product.cpu.abilist`.

A reinicialização preserva aplicativos e dados no disco do AVD. Snapshots capturam o estado do AVD e reverterão mudanças feitas desde a captura. A compatibilidade pode mudar após atualizar o emulador, a imagem ou a configuração de hardware. Para uma cópia independente enquanto o AVD estiver desligado, arquive a pasta de estado e registre a versão do emulador, a imagem, o SDK e o caminho absoluto do AVD. Para recuperar esse arquivo, preserve os caminhos originais e deixe uma cópia do estado atual antes de substituir qualquer dado.

## Testes

Execute `.\Android.ps1 Test` para verificar inicialização, conexão ADB, API, ABI, tipo de build, SELinux e persistência de um arquivo temporário após desligar e ligar. O comando mede os tempos e salva uma captura PNG no estado local. Abra a captura e confira a janela do emulador para validar a interface. Com o AVD desligado no início, o primeiro tempo mede uma inicialização fria.

Para testar instalação e persistência do pacote, execute `.\Android.ps1 Test -Apk 'C:APKs	este.apk' -Package com.exemplo.teste`. Use um APK próprio destinado ao teste. A instalação permanece disponível até que você execute Uninstall. Valide dados internos registrando um valor no app pela interface e conferindo o mesmo valor após Restart. Use Resources para consultar CPU e memória durante o fluxo que deseja medir.

## Diagnóstico

- **Aceleração indisponível**. Verifique SVM no UEFI e WHPX no Windows. O código 6 observado neste computador indica que o emulador detectou Hyper-V, mas ainda não conseguiu usar WHPX.
- **Falha ao buscar manifestos**. Use o SDK Manager do Android Studio para instalar Android Emulator, Android SDK Platform-Tools e a imagem Android 12 Google Play x86_64. Aponte `ANDROID_HOME` para esse SDK e repita Setup. O erro foi observado nesta sessão do Windows mesmo com acesso HTTPS pelo curl.
- **Janela vazia ou falha gráfica**. Consulte Diagnose e tente `.\Android.ps1 Configure -Gpu software` antes de iniciar novamente. Essa opção altera o renderizador gráfico. A aceleração da CPU permanece obrigatória.
- **Falha na instalação do APK**. Confira a mensagem do ADB, a assinatura da versão já instalada, a API mínima e as ABIs que o APK oferece.
- **Dados do AVD original**. Use o mesmo `ANDROID12_LOCAL_HOME` em todos os comandos e no painel para reencontrar o AVD já criado.

Referências oficiais

- [Aceleração do Android Emulator no Windows](https://developer.android.com/studio/run/emulator-acceleration)
- [Ferramentas de linha de comando e imagem do SDK](https://developer.android.com/tools/sdkmanager)
- [Downloads e hashes oficiais](https://developer.android.com/studio)
- [ADB](https://developer.android.com/tools/adb)
- [Snapshots do Android Emulator](https://developer.android.com/studio/run/emulator-snapshots)

