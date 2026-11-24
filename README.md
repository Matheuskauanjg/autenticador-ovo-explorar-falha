# Android 12 — ambiente de testes de APK

Ambiente de desenvolvimento para executar uma imagem oficial Android 12 (API 31), x86_64, Google Play. Não contém aplicativos de teste, root, alterações de segurança ou dados de usuários.

## GitHub Codespaces (experimental)

1. No GitHub, abra Code > Codespaces > Create codespace on main. Use uma máquina x86_64 com pelo menos 8 GB de RAM e espaço suficiente para o SDK.
2. No terminal, execute `bash android.sh setup`. Leia e aceite as licenças do SDK quando solicitado.
3. Execute `bash android.sh start`. Mantenha o terminal aberto. Aguarde a inicialização do Android.
4. Na aba Ports, encaminhe a porta 6080 como **Private**. Abra a URL da porta e acesse `/vnc.html`, conectando com a senha criada pelo script.
5. Em outro terminal, faça upload do seu APK para a pasta local apks/ e execute `bash android.sh install apks/meu-app.apk`.

Não torne portas públicas. ADB e VNC ficam locais. Não coloque APKs privados ou credenciais no Git. Use contas e dados de teste autorizados.

## Linux local (recomendado)

Instale as dependências (Ubuntu/Debian): curl, unzip, default-jdk, xvfb, x11vnc, novnc, websockify, libgl1, libegl1, libpulse0, libxcb-cursor0, libxkbcommon-x11-0, libnss3. Execute os mesmos comandos acima. Acesse http://localhost:6080/vnc.html.

## Diagnóstico

- `bash android.sh status`: verifica KVM e dispositivos ADB.
- `bash android.sh install caminho.apk`: instala APK comum compatível.
- `Ctrl+C`: encerra a sessão iniciada pelo script.
- Imagens x86_64 podem não executar todos os APKs ARM; APKs divididos e formatos APKM/XAPK exigem instalação apropriada.
- Codespaces não garante suporte ao Android Emulator dentro de containers. Sem /dev/kvm acessível, o script tenta emulação por software, que pode ser lenta ou falhar. Se ocorrer, use Android Studio local com aceleração habilitada.
- Apps corporativos podem rejeitar emuladores. O ambiente não tenta contornar essas políticas.

Documentação: https://developer.android.com/studio/run/emulator-commandline e https://developer.android.com/studio/run/emulator-acceleration.

Este projeto é uma configuração de ambiente, não uma ROM compilada. A execução no Codespaces ainda precisa ser validada.
