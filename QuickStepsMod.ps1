function Connect-Exchange
{ 
    param( 
    	[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials
    )  
 	Begin
		 {
		## Load Managed API dll  
		###CHECK FOR EWS MANAGED API, IF PRESENT IMPORT THE HIGHEST VERSION EWS DLL, ELSE EXIT
		$EWSDLL = (($(Get-ItemProperty -ErrorAction SilentlyContinue -Path Registry::$(Get-ChildItem -ErrorAction SilentlyContinue -Path 'Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Exchange\Web Services'|Sort-Object Name -Descending| Select-Object -First 1 -ExpandProperty Name)).'Install Directory') + "Microsoft.Exchange.WebServices.dll")
		if (Test-Path $EWSDLL)
		    {
		    Import-Module $EWSDLL
		    }
		else
		    {
		    "$(get-date -format yyyyMMddHHmmss):"
		    "This script requires the EWS Managed API 1.2 or later."
		    "Please download and install the current version of the EWS Managed API from"
		    "http://go.microsoft.com/fwlink/?LinkId=255472"
		    ""
		    "Exiting Script."
		    exit
		    } 
  
		## Set Exchange Version  
		$ExchangeVersion = [Microsoft.Exchange.WebServices.Data.ExchangeVersion]::Exchange2010_SP2  
		  
		## Create Exchange Service Object  
		$service = New-Object Microsoft.Exchange.WebServices.Data.ExchangeService($ExchangeVersion)  
		  
		## Set Credentials to use two options are availible Option1 to use explict credentials or Option 2 use the Default (logged On) credentials  
		  
		#Credentials Option 1 using UPN for the windows Account  
		#$psCred = Get-Credential  
		$creds = New-Object System.Net.NetworkCredential($Credentials.UserName.ToString(),$Credentials.GetNetworkCredential().password.ToString())  
		$service.Credentials = $creds      
		#Credentials Option 2  
		#service.UseDefaultCredentials = $true  
		 #$service.TraceEnabled = $true
		## Choose to ignore any SSL Warning issues caused by Self Signed Certificates  
		  
		## Code From http://poshcode.org/624
		## Create a compilation environment
		$Provider=New-Object Microsoft.CSharp.CSharpCodeProvider
		$Compiler=$Provider.CreateCompiler()
		$Params=New-Object System.CodeDom.Compiler.CompilerParameters
		$Params.GenerateExecutable=$False
		$Params.GenerateInMemory=$True
		$Params.IncludeDebugInformation=$False
		$Params.ReferencedAssemblies.Add("System.DLL") | Out-Null

$TASource=@'
  namespace Local.ToolkitExtensions.Net.CertificatePolicy{
    public class TrustAll : System.Net.ICertificatePolicy {
      public TrustAll() { 
      }
      public bool CheckValidationResult(System.Net.ServicePoint sp,
        System.Security.Cryptography.X509Certificates.X509Certificate cert, 
        System.Net.WebRequest req, int problem) {
        return true;
      }
    }
  }
'@ 
		$TAResults=$Provider.CompileAssemblyFromSource($Params,$TASource)
		$TAAssembly=$TAResults.CompiledAssembly

		## We now create an instance of the TrustAll and attach it to the ServicePointManager
		$TrustAll=$TAAssembly.CreateInstance("Local.ToolkitExtensions.Net.CertificatePolicy.TrustAll")
		[System.Net.ServicePointManager]::CertificatePolicy=$TrustAll

		## end code from http://poshcode.org/624
		  
		## Set the URL of the CAS (Client Access Server) to use two options are availbe to use Autodiscover to find the CAS URL or Hardcode the CAS to use  
		  
		#CAS URL Option 1 Autodiscover  
		$service.AutodiscoverUrl($MailboxName,{$true})  
		Write-host ("Using CAS Server : " + $Service.url)   
		   
		#CAS URL Option 2 Hardcoded  
		  
		#$uri=[system.URI] "https://casservername/ews/exchange.asmx"  
		#$service.Url = $uri    
		  
		## Optional section for Exchange Impersonation  
		  
		#$service.ImpersonatedUserId = new-object Microsoft.Exchange.WebServices.Data.ImpersonatedUserId([Microsoft.Exchange.WebServices.Data.ConnectingIdType]::SmtpAddress, $MailboxName) 
		if(!$service.URL){
			throw "Error connecting to EWS"
		}
		else
		{		
			return $service
		}
	}
}

function ConvertFolderid{
	param(
		[Parameter(Position=0, Mandatory=$true)] [string]$hexid,
		[Parameter(Position=1, Mandatory=$true)] [Microsoft.Exchange.WebServices.Data.ExchangeService]$service,
		[Parameter(Position=2, Mandatory=$true)] [string]$MailboxName
	)
	Begin
	{
	    $aiItem = New-Object Microsoft.Exchange.WebServices.Data.AlternateId    
	    $aiItem.Mailbox = $MailboxName    
	    $aiItem.UniqueId = $hexId  
	    $aiItem.Format = [Microsoft.Exchange.WebServices.Data.IdFormat]::HexEntryId;    
	    return $service.ConvertId($aiItem, [Microsoft.Exchange.WebServices.Data.IdFormat]::EWSId)   
	}
} 
####################### 
<# 
.SYNOPSIS 
 Gets the QuickSteps folder in a Mailbox using the  Exchange Web Services API 
 
.DESCRIPTION 
   Gets the QuickSteps folder in a Mailbox using the  Exchange Web Services API 
  
  Requires the EWS Managed API from https://www.microsoft.com/en-us/download/details.aspx?id=42951

.EXAMPLE 
	Example 1 To Gets the QuickSteps folder in a Mailbox using the  Exchange Web Services API
	Get-QuickStepsFolder -MailboxName mailbox@domain.com 

#> 
########################
function Get-QuickStepsFolder
{
	param(
		[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials,
		[Parameter(Position=2, Mandatory=$false)] [Microsoft.Exchange.WebServices.Data.ExchangeService]$service	
	)
	Begin
	{
		if(!$service){
			$service = Connect-Exchange -MailboxName $MailboxName -Credential $Credentials
		}
		$PidTagAdditionalRenEntryIdsEx = new-object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x36D9, [Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary)  
		$psPropset = new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)  
		$psPropset.Add($PidTagAdditionalRenEntryIdsEx)  
		$folderid= new-object Microsoft.Exchange.WebServices.Data.FolderId([Microsoft.Exchange.WebServices.Data.WellKnownFolderName]::Root,$MailboxName)     
		$IPM_ROOT = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$folderid,$psPropset)  
		$binVal = $null;  
		$AdditionalRenEntryIdsExCol = @{}  
		if($IPM_ROOT.TryGetProperty($PidTagAdditionalRenEntryIdsEx,[ref]$binVal)){  
		    $hexVal = [System.BitConverter]::ToString($binVal).Replace("-","");  
		    ##Parse Binary Value first word is Value type Second word is the Length of the Entry  
		    $Sval = 0;  
		    while(($Sval+8) -lt $hexVal.Length){  
		        $PtypeVal = $hexVal.SubString($Sval,4)  
		        $PtypeVal = $PtypeVal.SubString(2,2) + $PtypeVal.SubString(0,2)  
		        $Sval +=12;  
		        $PropLengthVal = $hexVal.SubString($Sval,4)  
		        $PropLengthVal = $PropLengthVal.SubString(2,2) + $PropLengthVal.SubString(0,2)  
		        $PropLength = [Convert]::ToInt64($PropLengthVal, 16)  
		        $Sval +=4;  
		        $ProdIdEntry = $hexVal.SubString($Sval,($PropLength*2))  
		        $Sval += ($PropLength*2)  
		        #$PtypeVal + " : " + $ProdIdEntry  
		        $AdditionalRenEntryIdsExCol.Add($PtypeVal,$ProdIdEntry)   
		    }     
		}
		$QuickStepsFolder = $null
		if($AdditionalRenEntryIdsExCol.ContainsKey("8007")){  
	    	$siId = ConvertFolderid -service $service -MailboxName $MailboxName -hexid $AdditionalRenEntryIdsExCol["8007"]  
	   		$QuickStepsFolderId = new-object Microsoft.Exchange.WebServices.Data.FolderId($siId.UniqueId.ToString())  
	    	$QuickStepsFolder = [Microsoft.Exchange.WebServices.Data.Folder]::Bind($service,$QuickStepsFolderId) 
		}
		else{
			Write-Host ("QuickSteps folder not found")
			throw ("QuickSteps folder not found")
		}
		return $QuickStepsFolder
  

	}
	
}

function Get-ExistingStepNames{
  param(
		[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [Microsoft.Exchange.WebServices.Data.Folder]$QuickStepsFolder	
	)
	Begin
	{
		$NameList = @{}
		$enc = [system.Text.Encoding]::ASCII
		$PR_ROAMING_XMLSTREAM = New-Object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x7C08,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary);  
		$psPropset= new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)  
		$psPropset.Add($PR_ROAMING_XMLSTREAM)
		#Define ItemView to retrive just 1000 Items    
		$ivItemView =  New-Object Microsoft.Exchange.WebServices.Data.ItemView(1000)
		$ivItemView.Traversal = [Microsoft.Exchange.WebServices.Data.ItemTraversal]::Associated
		$fiItems = $null    
		do{    
		    $fiItems = $QuickStepsFolder.FindItems($ivItemView)  
			if($fiItems.Items.Count -gt 0){
			    [Void]$service.LoadPropertiesForItems($fiItems,$psPropset)  
			    foreach($Item in $fiItems.Items){      
					$propval = $null
					if($Item.TryGetProperty($PR_ROAMING_XMLSTREAM,[ref]$propval)){
						[XML]$xmlVal = $enc.GetString($propval)
						if(!$NameList.ContainsKey($xmlVal.CombinedAction.Name.ToLower())){
							$NameList.Add($xmlVal.CombinedAction.Name.Trim().ToLower(),$xmlVal)
						}
					}         
			    }
			}    
		    $ivItemView.Offset += $fiItems.Items.Count    
		}while($fiItems.MoreAvailable -eq $true) 
		return $NameList
	}
}

function Get-ExistingSteps{
  param(
		[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [Microsoft.Exchange.WebServices.Data.Folder]$QuickStepsFolder	
	)
	Begin
	{
		$NameList = @{}
		$enc = [system.Text.Encoding]::ASCII
		$PR_ROAMING_XMLSTREAM = New-Object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x7C08,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary);  
		$psPropset= new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)  
		$psPropset.Add($PR_ROAMING_XMLSTREAM)
		#Define ItemView to retrive just 1000 Items    
		$ivItemView =  New-Object Microsoft.Exchange.WebServices.Data.ItemView(1000)
		$ivItemView.Traversal = [Microsoft.Exchange.WebServices.Data.ItemTraversal]::Associated
		$fiItems = $null    
		do{    
		    $fiItems = $QuickStepsFolder.FindItems($ivItemView)  
			if($fiItems.Items.Count -gt 0){
			    [Void]$service.LoadPropertiesForItems($fiItems,$psPropset)  
			    foreach($Item in $fiItems.Items){      
					$propval = $null
					if($Item.TryGetProperty($PR_ROAMING_XMLSTREAM,[ref]$propval)){
						[XML]$xmlVal = $enc.GetString($propval)
						if(!$NameList.ContainsKey($xmlVal.CombinedAction.Name.ToLower())){
							$NameList.Add($xmlVal.CombinedAction.Name.Trim().ToLower(),$Item)
						}
					}         
			    }
			}    
		    $ivItemView.Offset += $fiItems.Items.Count    
		}while($fiItems.MoreAvailable -eq $true) 
		return $NameList
	}
}
####################### 
<# 
.SYNOPSIS 
 Gets the existing Outlook Quick Steps from a Mailbox using the  Exchange Web Services API 
 
.DESCRIPTION 
   Gets the existing Outlook Quick Steps from a Mailbox using the  Exchange Web Services API 
  
  Requires the EWS Managed API from https://www.microsoft.com/en-us/download/details.aspx?id=42951

.EXAMPLE 
	Example 1 To Gets the existing Outlook Quick Steps from a Mailbox using the  Exchange Web Services API
	Get-QuickSteps -MailboxName mailbox@domain.com 
	This returns a HashTable of the QuickSteps to access a Quickstep within the collection use the Index value eg
    $QuickSteps = Get-QuickSteps -MailboxName mailbox@domain.com 
	$QuickSteps["clutter"]

#> 
########################
function Get-QuickSteps{
	param(
	    [Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials
	)
	Begin{
		#Connect
		$service = Connect-Exchange -MailboxName $MailboxName -Credential $Credentials
		$QuickStepsFolder = Get-QuickStepsFolder -MailboxName $MailboxName -service $service -Credentials $Credentials
		$ExistingSteps = Get-ExistingStepNames -MailboxName $MailboxName -QuickStepsFolder $QuickStepsFolder
		Write-Output $ExistingSteps
	}
}
####################### 
<# 
.SYNOPSIS 
 Exports an Outlook Quick Step XML settings from a QuickStep Item in a Mailbox using the  Exchange Web Services API 
 
.DESCRIPTION 
  Exports an Outlook Quick Step XML settings from a QuickStep Item in a Mailbox using the  Exchange Web Services API
  
  Requires the EWS Managed API from https://www.microsoft.com/en-us/download/details.aspx?id=42951

.EXAMPLE 
	Example 1 Exports an Outlook Quick Step XML settings from a QuickStep Item in a Mailbox to a file 
	Export-QuickStepXML -MailboxName mailbox@domain -Name 'Name of QuickStep' -FileName c:\temp\exportFile.xml

#> 
########################
function Export-QuickStepXML{
	param(
	    [Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials,
		[Parameter(Position=2, Mandatory=$true)] [string]$Name,
		[Parameter(Position=3, Mandatory=$true)] [string]$FileName
	)
	Begin{
		#Connect
		$service = Connect-Exchange -MailboxName $MailboxName -Credential $Credentials
		$QuickStepsFolder = Get-QuickStepsFolder -MailboxName $MailboxName -service $service -Credentials $Credentials
		$ExistingSteps = Get-ExistingSteps -MailboxName $MailboxName -QuickStepsFolder $QuickStepsFolder
		if($ExistingSteps.ContainsKey($Name.Trim().ToLower())){
			$PR_ROAMING_XMLSTREAM = New-Object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x7C08,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary);  
			$psPropset= new-object Microsoft.Exchange.WebServices.Data.PropertySet([Microsoft.Exchange.WebServices.Data.BasePropertySet]::FirstClassProperties)  
			$psPropset.Add($PR_ROAMING_XMLSTREAM)
			$propval = $null
			if($ExistingSteps[$Name.Trim().ToLower()].TryGetProperty($PR_ROAMING_XMLSTREAM,[ref]$propval)){
				[System.IO.File]::WriteAllBytes($FileName,$propval)
				Write-Host ('Exported to ' + $FileName)
			}
		}	
	}
}

function Create-QuickStepFromXML
{ 
    param( 
    	[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials,
		[Parameter(Position=2, Mandatory=$true)] [String]$XMLFileName
    )  
 	Begin
	{
		#Connect
		[xml]$QuickStepXML = Get-Content -Path $XMLFileName
		$Name = $QuickStepXML.CombinedAction.Name.ToLower()
		$service = Connect-Exchange -MailboxName $MailboxName -Credential $Credentials
		$QuickStepsFolder = Get-QuickStepsFolder -MailboxName $MailboxName -service $service -Credentials $Credentials
		$QuickStepItem = New-Object Microsoft.Exchange.WebServices.Data.EmailMessage -ArgumentList $service
		$QuickStepItem.ItemClass = "IPM.Microsoft.CustomAction"		
		$ExistingSteps = Get-ExistingStepNames -MailboxName $MailboxName -QuickStepsFolder $QuickStepsFolder
		if(!$ExistingSteps.ContainsKey($Name.Trim().ToLower())){
			$PR_ROAMING_XMLSTREAM = New-Object Microsoft.Exchange.WebServices.Data.ExtendedPropertyDefinition(0x7C08,[Microsoft.Exchange.WebServices.Data.MapiPropertyType]::Binary);  
			$enc = [system.Text.Encoding]::ASCII
			$QuickStepItem.SetExtendedProperty($PR_ROAMING_XMLSTREAM,$enc.GetBytes((Get-Content -Path $XMLFileName)))
			$QuickStepItem.IsAssociated = $true
			$QuickStepItem.Save($QuickStepsFolder.Id)
			Write-host ("Created QuickStep " + $Name)
		}
		else
		{
			throw ("Step with Name " + $DisplayName + " already exists")
		}

	

	}
}
####################### 
<# 
.SYNOPSIS 
 Deletes an Outlook Quick Step from a Mailbox using the  Exchange Web Services API 
 
.DESCRIPTION 
   Deletes an Outlook Quick Step from a Mailbox using the  Exchange Web Services API 
  
  Requires the EWS Managed API from https://www.microsoft.com/en-us/download/details.aspx?id=42951

.EXAMPLE 
	Example 1 To Delete an Outlook Quick Step from a Mailbox give the name of the Quickstep 
	Delete-QuickStep -MailboxName mailbox@domain -Name 'Name of QuickStep'

#> 
########################
function Delete-QuickStep{
    param( 
    	[Parameter(Position=0, Mandatory=$true)] [string]$MailboxName,
		[Parameter(Position=1, Mandatory=$true)] [PSCredential]$Credentials,
		[Parameter(Position=2, Mandatory=$true)] [String]$Name
    )  
 	Begin
	{
		#Connect
		$service = Connect-Exchange -MailboxName $MailboxName -Credential $Credentials
		$QuickStepsFolder = Get-QuickStepsFolder -MailboxName $MailboxName -service $service -Credentials $Credentials
		$ExistingSteps = Get-ExistingSteps -MailboxName $MailboxName -QuickStepsFolder $QuickStepsFolder
		if($ExistingSteps.ContainsKey($Name.Trim().ToLower())){
			$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes",""  
            $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No",""            
            $choices = [System.Management.Automation.Host.ChoiceDescription[]]($yes,$no)  
            $message = "Do you want to Delete QuickStep with Name " + $Name.Trim()
			$result = $Host.UI.PromptForChoice($caption,$message,$choices,1)  
            if($result -eq 0) {                       
                $ExistingSteps[$Name.Trim().ToLower()].Delete([Microsoft.Exchange.WebServices.Data.DeleteMode]::HardDelete) 
				Write-Host ("QuickStep Deleted")
            } 
			else{
				Write-Host ("No Action Taken")
			}
			
		}
		else{
			Write-Host -ForegroundColor Yellow ("No QuickStep found")
		}
	}
}