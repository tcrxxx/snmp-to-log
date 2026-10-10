# SNMP to Log - Coletor Horário para Brother DCP-T530DW (Raspberry Pi)

Projeto em Shell Script (Bash) otimizado para o **Raspberry Pi** para monitorar e registrar hora a hora via **cron**:
1. **Contagem total de páginas impressas** (via MIB universal RFC 3805).
2. **Percentual de níveis de tinta** (BK, C, M, Y) via OID de manutenção da Brother.

---

## 📁 Estrutura do Projeto

Caminho padrão de instalação recomendado: `/opt/snmp-to-log`
Caminho padrão de armazenamento dos logs: `/opt/snmp-to-log/log/printer.log`

```text
/opt/snmp-to-log/
├── config/
│   ├── printer.conf           # Configuração ativa da Brother DCP-T530DW
│   └── printer.conf.example   # Modelo de referência
├── scripts/
│   ├── printer_log.sh         # Coleta contagem de páginas e % de tinta
│   ├── test_snmp.sh           # Diagnóstico detalhado de comunicação SNMP
│   └── setup_cron.sh          # Instala ou remove tarefa do crontab
├── log/
│   └── printer.log            # Arquivo com o histórico horário gerado
├── install.sh                 # Instalador e preparador de permissões
├── .gitignore
└── README.md
```

---

## 💡 Como funciona o monitoramento de tinta na Brother DCP-T530DW?

Diferente de impressoras laser (onde cartuchos possuem chips eletrônicos dedicados), impressoras da linha **InkBenefit / Tanque de Tinta (DCP-T)** medem o nível por contagem de gotas/páginas e sensores ópticos.

* A MIB padrão (`prtMarkerSuppliesTable`) frequentemente retorna `-3` (nível não suportado/apenas presente).
* Por isso, este script utiliza o OID proprietário de manutenção da Brother:
  ```text
  1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.8.0 (brInfoMaintenance)
  ```
  Ele retorna uma cadeia hexadecimal decodificada automaticamente pelo script para extrair as tags dos consumíveis:
  * **BK (Preto):** Tag `6F` ou `81`
  * **C (Ciano):** Tag `70` ou `82`
  * **M (Magenta):** Tag `71` ou `83`
  * **Y (Amarelo):** Tag `72` ou `84`

---

## 🚀 Instalação no Raspberry Pi

### 1. Clonar ou copiar o projeto para `/opt/snmp-to-log`
```bash
sudo mkdir -p /opt/snmp-to-log
sudo chown -R $USER:$USER /opt/snmp-to-log
cd /opt/snmp-to-log

# Clone do repositório (ou copie os arquivos para cá)
git clone https://github.com/SEU_USUARIO/snmp-to-log.git .
```

### 2. Executar o instalador
```bash
chmod +x install.sh
./install.sh
```

---

## ⚙️ Configuração (`config/printer.conf`)

Edite o arquivo de configuração para inserir o IP da sua impressora:

```bash
nano config/printer.conf
```

Exemplo pronto gerado pelo projeto:
```bash
PRINTER_IP="192.168.1.50"
SNMP_COMMUNITY="public"
SNMP_VERSION="2c"
SNMP_TIMEOUT="3"
SNMP_RETRIES="2"

# Páginas e Tinta
OID_PAGE_COUNT="1.3.6.1.2.1.43.10.2.1.4.1.1"
LOG_INK_LEVELS="true"
OID_BROTHER_MAINTENANCE="1.3.6.1.4.1.2435.2.3.9.4.2.1.5.5.8.0"

# Armazenamento padrão dos logs
LOG_FILE="/opt/snmp-to-log/log/printer.log"
LOG_OFFLINE_EVENTS="false"
```

---

## 🔍 Teste de Diagnóstico

Antes de colocar no cron, execute o teste para validar a resposta da impressora:

```bash
./scripts/test_snmp.sh
```

Saída esperada:
```text
==========================================================
    TESTE DE DIAGNÓSTICO SNMP - BROTHER DCP-T530DW        
==========================================================
IP Alvo:       192.168.1.50
...
[1/4] Identificando dispositivo...
  -> Identificação: Brother NC-8300w, Firmware Ver.1.00
[2/4] Testando contador total de páginas...
  -> SUCESSO: 1420 páginas registradas na memória.
[3/4] Testando leitura de tinta...
  -> Preto (BK):    85%
  -> Ciano (C):     90%
  -> Magenta (M):   90%
  -> Amarelo (Y):   80%
[4/4] Verificando diretório de log...
  -> Diretório de log (/opt/snmp-to-log/log) com permissão de escrita OK.
```

---

## 📝 Teste Manual de Registro

Execute o script de log manualmente:
```bash
./scripts/printer_log.sh
```

Consulte o arquivo gerado:
```bash
cat /opt/snmp-to-log/log/printer.log
```

Formato do log gravado:
```text
2026-10-05 22:00:00 | Paginas: 1420 | Tinta: BK: 85% | C: 90% | M: 90% | Y: 80%
2026-10-05 23:00:00 | Paginas: 1425 | Tinta: BK: 85% | C: 90% | M: 90% | Y: 80%
```

---

## ⏰ Agendamento no Cron (A Cada 5 Minutos)

Use o helper para cadastrar no crontab do Raspberry Pi:

```bash
./scripts/setup_cron.sh
```

Para conferir o agendamento:
```bash
./scripts/setup_cron.sh --status
```
*(Ele adiciona `*/5 * * * * /opt/snmp-to-log/scripts/printer_log.sh >/dev/null 2>&1`, rodando a cada 5 minutos).*
