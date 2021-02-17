function Get-NumberQMessages {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $StorageAccount,
        [Parameter(Mandatory = $true)]
        [string]
        $QueueName,
        [Parameter(Mandatory = $true)]
        [string]
        $SASString,
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 32)]
        [int]
        $MessageCount = 32
    )

    begin {
        $moremessages = $true
        $query = '?numofmessages={0}&{1}' -f $MessageCount, $SASString
        $uri = ([System.UriBuilder]::new('https', "$StorageAccount.queue.core.windows.net", '443', "$QueueName/messages", $query)).Uri
    }

    process {
        $qMessages = while ($moremessages -eq $true) {
            [xml]$response = (Invoke-RestMethod -Uri $uri) -replace '\xEF\xBB\xBF', '' # Fixerate weird UTF8 BOM characters
            if (($response.QueueMessagesList.QueueMessage).count -lt 32) {
                $moremessages = $false
            }
            Write-Output $response.QueueMessagesList.QueueMessage
        }
        $messageTexts = foreach ($message in $qMessages) {
            $encMessage = $message.MessageText
            $encMessageBytes = [Convert]::FromBase64String($encMessage)
            $messageString = [Text.Encoding]::UTF8.GetString($encMessageBytes)
            Write-Output $messageString
        }
    }

    end {
        return $messageTexts
    }
}

function New-NumberQMessage {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]
        $StorageAccount,
        [Parameter(Mandatory = $true)]
        [string]
        $QueueName,
        [Parameter(Mandatory = $true)]
        [string]
        $SASString,
        [Parameter(Mandatory = $true)]
        [string]
        $MessageText,
        [Parameter(Mandatory = $false)]
        [ValidateRange(86400, 604800)]
        [int]
        $MessageTTLSeconds = 86400
    )

    begin {
        $query = '?messagettl={0}&{1}' -f $MessageTTLSeconds, $SASString
        $uri = ([System.UriBuilder]::new('https', "$StorageAccount.queue.core.windows.net", '443', "$QueueName/messages", $query)).Uri
        $QueueMessageBytes = [Text.Encoding]::UTF8.GetBytes($MessageText)
        $QueueMessage = [Convert]::ToBase64String($QueueMessageBytes)
        $body = @"
<?xml version="1.0" encoding="utf-8"?>
<QueueMessagesList>
    <QueueMessage>
        <MessageText>$QueueMessage</MessageText>
    </QueueMessage>
</QueueMessagesList>
"@
    }

    process {
        [xml]$newmessage = (Invoke-RestMethod -Uri $uri -Method Post -Body $body) -replace '\xEF\xBB\xBF', '' # Fixerate weird UTF8 BOM characters
    }

    end {
        return $newmessage
    }
}
