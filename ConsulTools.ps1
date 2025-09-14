$CONSUL_HOST = "localhost:8500"
$CONSUL_TOKEN = ""

#Gestisce l'injection del token nell'header delle richieste.
function Invoke-ConsulRestMethod {
    param(
        [string]$Method = "GET",
        [string]$Uri,
        [object]$Body = $null,
        [string]$ContentType = "application/json"
    )

    $headers = @{}
    if ($CONSUL_TOKEN -ne "") {
        $headers["X-Consul-Token"] = $CONSUL_TOKEN
    }

    $params = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($Body) {
        $params["Body"] = $Body
        $params["ContentType"] = $ContentType
    }

    return Invoke-RestMethod @params
}

function Costruisci-DeregistrationBody {
    param (
        [Parameter(Mandatory=$true)]
        $Istanza
    )

    return @{
        Node      = $Istanza.Node
        ServiceID = $Istanza.ServiceID
        # Datacenter opzionale, puoi aggiungerlo se necessario
        # Datacenter = "dc1"
    } | ConvertTo-Json -Depth 5
}

function Mostra-Menu-Frecce($titolo, $opzioni) {
    $indice = 0
    do {
        Clear-Host
        Write-Host "===================================================="
        Write-Host "$titolo - HOST: $CONSUL_HOST"
        Write-Host "===================================================="
        for ($i = 0; $i -lt $opzioni.Length; $i++) {
            if ($i -eq $indice) {
                Write-Host "➡️  $($opzioni[$i])" -ForegroundColor Cyan
            } else {
                Write-Host "   $($opzioni[$i])"
            }
        }

        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        switch ($key.VirtualKeyCode) {
            38 { if ($indice -gt 0) { $indice-- } } # Freccia Su
            40 { if ($indice -lt $opzioni.Length - 1) { $indice++ } } # Freccia Giù
            13 { return $indice } # Invio
        }
    } while ($true)
}

function Nome-Servizi {
    $SERVICES_ENDPOINT = "$CONSUL_HOST/v1/catalog/services"
    $SERVICES = Invoke-ConsulRestMethod -Uri $SERVICES_ENDPOINT
    return $SERVICES.PSObject.Properties.Name
}

function Visualizza-Servizi {
	Clear-Host  # <--- Aggiungi questa riga per pulire lo schermo
    Write-Host "🔄 Recupero l'elenco dei servizi registrati su Consul..."
    $SERVICE_NAMES = Nome-Servizi

    foreach ($SERVICE in $SERVICE_NAMES) {
        Write-Host "`n🔹 Servizio: ${SERVICE}" -ForegroundColor Magenta
        $INSTANCES_ENDPOINT = "$CONSUL_HOST/v1/catalog/service/$SERVICE"
        $INSTANCES = Invoke-ConsulRestMethod -Uri $INSTANCES_ENDPOINT
		
		$INSTANCES = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/catalog/service/$SERVICE"
        foreach ($INSTANCE in $INSTANCES) {
           Write-Host "  🔸 ID:$($INSTANCE.ID) | Hostname: $($INSTANCE.Node)  |  Address: $($INSTANCE.Address) | ServiceAddress: $($INSTANCE.ServiceAddress):$($INSTANCE.ServicePort) " -ForegroundColor White
        }
        Write-Host ""
    }
}

function Deregister-Servizio {
    $SERVICE_NAMES = Nome-Servizi
    if (-not $SERVICE_NAMES) {
        Write-Host "❌ Nessun servizio disponibile."
        return
    }

    $opzioni = @("🔙 Torna al menu") + $SERVICE_NAMES
    $selezione = Mostra-Menu-Frecce "❌ Seleziona un servizio da deregistrare" $opzioni

    if ($selezione -eq 0) { return }
    $SELECTED_SERVICE = $SERVICE_NAMES[$selezione - 1]

    Write-Host "🔄 Recupero istanze del servizio $SELECTED_SERVICE..."
    $INSTANCES = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/catalog/service/$SELECTED_SERVICE"

    foreach ($INSTANCE in $INSTANCES) {
        Write-Host "🔴 Deregistrazione istanza $($INSTANCE.ServiceID)..."
		$body = Costruisci-DeregistrationBody -Istanza $INSTANCE
		$DEREGISTER_ENDPOINT = "$CONSUL_HOST/v1/agent/service/deregister/$($INSTANCE.ServiceID)"
		Invoke-ConsulRestMethod -Method PUT -Uri $DEREGISTER_ENDPOINT -Body $body
		$DEREGISTER_ENDPOINT = "$CONSUL_HOST/v1/catalog/deregister"
        Invoke-ConsulRestMethod -Method PUT -Uri $DEREGISTER_ENDPOINT -Body $body
		
    }

    Write-Host "✅ Istanze di $SELECTED_SERVICE deregistrate con successo."
}

function Deregister-Istanza-Servizio {
    while ($true) {
        $SERVICE_NAMES = Nome-Servizi
        $opzioni = @("🔙 Torna al menu") + $SERVICE_NAMES
        $sceltaServizio = Mostra-Menu-Frecce "❌ Seleziona il servizio" $opzioni
        if ($sceltaServizio -eq 0) { return }

        $SELECTED_SERVICE = $SERVICE_NAMES[$sceltaServizio - 1]
        $INSTANCES = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/catalog/service/$SELECTED_SERVICE"

        if (-not $INSTANCES) {
            Write-Host "❌ Nessuna istanza trovata."
            continue  # Torna alla selezione del servizio
        }

        do {
            $istanzeDescrizioni = @("🔙 Torna al menu") + ($INSTANCES | ForEach-Object {
                "Nodo: $($_.Node) | Indirizzo: $($_.Address) | ID: $($_.ServiceID)"
            })

            $sceltaIstanza = Mostra-Menu-Frecce "❌ Seleziona l'istanza da deregistrare per $SELECTED_SERVICE" $istanzeDescrizioni
            if ($sceltaIstanza -eq 0) { break }  # Torna alla selezione del servizio

            $INSTANCE = $INSTANCES[$sceltaIstanza - 1]
          
            Write-Host "🔴 Deregistrazione $($ISTANZA.ServiceID)... $INSTANCE"
            $body = Costruisci-DeregistrationBody -Istanza $INSTANCE
			$DEREGISTER_ENDPOINT = "$CONSUL_HOST/v1/agent/service/deregister/$($INSTANCE.ServiceID)"
			Invoke-ConsulRestMethod -Method PUT -Uri $DEREGISTER_ENDPOINT -Body $body
			$DEREGISTER_ENDPOINT = "$CONSUL_HOST/v1/catalog/deregister"
			Invoke-ConsulRestMethod -Method PUT -Uri $DEREGISTER_ENDPOINT -Body $body
            Write-Host "✅ Istanza deregistrata."
			Write-Host "BODY : $body"
			Pause
            $INSTANCES = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/catalog/service/$SELECTED_SERVICE"
        } while ($INSTANCES.Count -gt 0)

        if ($INSTANCES.Count -eq 0) {
            Write-Host "✅ Tutte le istanze per $SELECTED_SERVICE sono state rimosse."
        }
    }
}


function Deregister-Servizi {
    $SERVICE_NAMES = Nome-Servizi
    $continua = Read-Host "⚠️ Eliminare tutte le istanze (tranne consul)? (y/n)"
    if ($continua -ne 'y') {
        Write-Host "🚫 Operazione annullata."
        return
    }

    foreach ($SERVICE_NAME in $SERVICE_NAMES) {
        if ($SERVICE_NAME -eq "consul") { continue }

        $INSTANCES = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/catalog/service/$SERVICE_NAME"
        foreach ($INSTANCE in $INSTANCES) {
            $body = Costruisci-DeregistrationBody -Istanza $INSTANCE
			$DEREGISTER_ENDPOINT = "$CONSUL_HOST/v1/agent/service/deregister/$($INSTANCE.ServiceID)"
			Invoke-ConsulRestMethod -Method PUT -Uri $DEREGISTER_ENDPOINT -Body $body
			$DEREGISTER_ENDPOINT = "$CONSUL_HOST/v1/catalog/deregister"
			Invoke-ConsulRestMethod -Method PUT -Uri $DEREGISTER_ENDPOINT -Body $body
        }
        Write-Host "✅ $SERVICE_NAME rimosso."
    }
}

# Funzione per il backup delle chiavi con selezione file
function Backup-KV {
    Add-Type -AssemblyName System.Windows.Forms
    $SaveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
    $SaveFileDialog.Filter = "JSON Files (*.json)|*.json"
    $SaveFileDialog.Title = "Scegli dove salvare il backup"
    $SaveFileDialog.FileName = "consul_kv_backup.json"

    if ($SaveFileDialog.ShowDialog() -eq "OK") {
        $BACKUP_FILE = $SaveFileDialog.FileName
        Write-Host "💾 Eseguo il backup delle chiavi in $BACKUP_FILE..."
        $response = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/kv/?recurse=true"

        if ($response -eq $null) {
            Write-Host "❌ Errore: Nessuna chiave trovata."
            return
        }

        # Decodifica i valori Base64 e crea un oggetto con i dati leggibili
        $backupData = @()
        foreach ($entry in $response) {
            $decodedValue = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($entry.Value))
            $backupData += @{
                Key   = $entry.Key
                Value = $decodedValue
            }
        }

        # Salva i dati in formato JSON
        $backupData | ConvertTo-Json -Depth 10 | Out-File $BACKUP_FILE
        Write-Host "✅ Backup completato!"
    } else {
        Write-Host "❌ Operazione annullata."
    }
}

# Funzione per il restore delle chiavi con selezione file
function Restore-KV {
    Add-Type -AssemblyName System.Windows.Forms
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Filter = "JSON Files (*.json)|*.json"
    $OpenFileDialog.Title = "Seleziona il file di backup da ripristinare"

    if ($OpenFileDialog.ShowDialog() -eq "OK") {
        $BACKUP_FILE = $OpenFileDialog.FileName
        Write-Host "🔄 Ripristino delle chiavi da $BACKUP_FILE..."

        if (-Not (Test-Path $BACKUP_FILE)) {
            Write-Host "❌ Errore: File non trovato!"
            return
        }

        # Chiedi all'utente se vuole cancellare tutte le chiavi esistenti prima del ripristino
        $conferma = Read-Host "⚠️ Vuoi eliminare TUTTE le chiavi attualmente presenti su Consul prima del restore? (y/n)"
        if ($conferma -eq 'y') {
            Write-Host "🧹 Eliminazione di tutte le chiavi esistenti..."
            $chiaviCorrenti = Invoke-ConsulRestMethod -Uri "$CONSUL_HOST/v1/kv/?recurse=true"

            foreach ($chiave in $chiaviCorrenti) {
                $key = $chiave.Key
                Invoke-ConsulRestMethod -Method DELETE -Uri "$CONSUL_HOST/v1/kv/$key"
            }
            Write-Host "✅ Tutte le chiavi esistenti sono state eliminate."
        } else {
            Write-Host "ℹ️ Le chiavi esistenti NON verranno eliminate."
        }

        $backupData = Get-Content $BACKUP_FILE | ConvertFrom-Json
        foreach ($entry in $backupData) {
            $key = $entry.Key
            $value = $entry.Value

            Invoke-ConsulRestMethod -Method Put -Uri "$CONSUL_HOST/v1/kv/$key" -Body $value -ContentType "text/plain"
        }

        Write-Host "✅ Restore completato!"
    } else {
        Write-Host "❌ Operazione annullata."
    }
}


# Funzione per caricare un file di property o YAML in Consul KV con struttura configurata
function Importa-Config-KV {
    Add-Type -AssemblyName System.Windows.Forms
    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $OpenFileDialog.Filter = "Config Files (*.properties, *.yml)|*.properties;*.yml"
    $OpenFileDialog.Title = "Seleziona il file di configurazione da importare"

    if ($OpenFileDialog.ShowDialog() -eq "OK") {
        $CONFIG_FILE = $OpenFileDialog.FileName
        $FileNameWithoutExtension = [System.IO.Path]::GetFileNameWithoutExtension($CONFIG_FILE)
        $ConsulKeyPath = "config/$FileNameWithoutExtension/data"

        Write-Host "🔄 Importazione del file $CONFIG_FILE sotto $ConsulKeyPath..."

        if (-Not (Test-Path $CONFIG_FILE)) {
            Write-Host "❌ Errore: File non trovato!"
            return
        }

        # Determina il tipo di file e carica correttamente
        $fileExtension = [System.IO.Path]::GetExtension($CONFIG_FILE).ToLower()
        
        $fileContent = ""
        if ($fileExtension -eq ".yml" -or $fileExtension -eq ".yaml") {
            # Gestione YAML
            Write-Host "📄 File YAML rilevato, analizzando..."
            $fileContent = Get-Content $CONFIG_FILE -Raw
        } elseif ($fileExtension -eq ".properties") {
            # Gestione Properties
            Write-Host "📄 File Properties rilevato, analizzando..."
            $propertiesContent = Get-Content $CONFIG_FILE -Raw
            $propertiesDictionary = @{}
            
            $propertiesContent -split "`n" | ForEach-Object {
                $line = $_.Trim()
                if ($line -match "^(?<key>[^=]+)=(?<value>.+)$") {
                    $propertiesDictionary[$matches['key'].Trim()] = $matches['value'].Trim()
                }
            }
            $fileContent = ($propertiesDictionary.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "`n"
        }

        # Invia il contenuto a Consul KV
        Invoke-ConsulRestMethod -Method Put -Uri "$CONSUL_HOST/v1/kv/$ConsulKeyPath" -Body $fileContent -ContentType "text/plain"
        Write-Host "✅ Importazione completata sotto $ConsulKeyPath!"
    } else {
        Write-Host "❌ Operazione annullata."
    }
}

#Consente di cambiare il server a cui si ci connette.
function Cambia-Consul-Host {
    $NuovoIP = Read-Host "🔧 Inserisci il nuovo indirizzo di Consul (es. 192.168.1.100:8500)"
    $NuovoConsulHost = "http://$NuovoIP"

    # Chiedi SUBITO se vuole cambiare il token
    $cambiaToken = Read-Host "❓ Vuoi inserire un nuovo token per il nuovo host? (s/n)"
    $tokenDaUsare = $CONSUL_TOKEN

    if ($cambiaToken -eq "s") {
        $tokenDaUsare = Read-Host "🔐 Inserisci il nuovo token Consul"
    }

    try {
        # Imposta temporaneamente il token da usare per il test
        $tokenVecchio = $CONSUL_TOKEN
        $script:CONSUL_TOKEN = $tokenDaUsare

        Write-Host "⏳ Test della connessione a $NuovoConsulHost ..."
        $test = Invoke-ConsulRestMethod -Uri "$NuovoConsulHost/v1/status/leader" -TimeoutSec 3

        if ($test) {
            $script:CONSUL_HOST = $NuovoConsulHost
            Write-Host "✅ Connessione riuscita!"
            Write-Host "🌐 Nuovo CONSUL_HOST: $CONSUL_HOST"
            Write-Host "🔐 Token aggiornato con successo."
        } else {
            Write-Host "⚠️ Il server ha risposto, ma non sembra un'istanza valida di Consul."
            $script:CONSUL_TOKEN = $tokenVecchio
        }
    }
    catch {
        Write-Host "❌ Errore: $_"
        $script:CONSUL_TOKEN = $tokenVecchio
    }
}



function Cambia-Consul-Token {
    $nuovoToken = Read-Host "🔐 Inserisci il nuovo token Consul"
    $script:CONSUL_TOKEN = $nuovoToken
    Write-Host "✅ Token aggiornato."
}

function Mostra-MenuInterattivo {
    $opzioni = @(
        "🔎 Visualizza i servizi",
        "❌ Deregistra un servizio",
        "❌ Deregistra TUTTI i servizi (tranne consul)",
        "❌ Deregistra una specifica istanza di un servizio",
        "💾 Backup delle chiavi KV",
        "🔄 Restore delle chiavi KV",
        "📤 Importa un file di configurazione in Consul",
        "🔧 Cambia Consul Host",
        "🔐 Cambia Token Consul",
        "🚪 Esci"
    )
    return Mostra-Menu-Frecce "📋 MAIN MENU" $opzioni
}

function Main {
	$host.ui.RawUI.WindowTitle = "Consul Tools"
    $esci = $false
    do {
        $scelta = Mostra-MenuInterattivo
        switch ($scelta) {
			0 { Visualizza-Servizi }
			1 { Deregister-Servizio }
			2 { Deregister-Servizi }
			3 { Deregister-Istanza-Servizio }
			4 { Backup-KV }
			5 { Restore-KV }
			6 { Importa-Config-KV }
			7 { Cambia-Consul-Host }
			8 { Cambia-Consul-Token }
			9 {
				Write-Host "n🚪 Uscita dal programma.n" -ForegroundColor Yellow
				$esci = $true
			}
		}


       if (-not $esci) {
			Write-Host "`nPremi INVIO o ESC per tornare al menu..." -ForegroundColor DarkGray
			do {
				$key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
			} while ($key.VirtualKeyCode -ne 13 -and $key.VirtualKeyCode -ne 27)
		}
    } while (-not $esci)

}

Main
