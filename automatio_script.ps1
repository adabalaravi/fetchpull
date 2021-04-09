workflow Payments_Lab_Mgmt
{
  Param(
    [Parameter(Mandatory=$true)]
    [String]$TagName,
    [Parameter(Mandatory=$true)]
    [String[]]$TagValues,
    [Parameter(Mandatory=$true)]
    [Boolean]$Shutdown,
    [Parameter(Mandatory=$false)]
    [Boolean]$StartServices
  )
  function Service_Start_Stop  {
    param(
      [Parameter(Mandatory=$true)]
      [String]$VmName,
      [Parameter(Mandatory=$true)]
      [String]$StorageAccountName,
      [Parameter(Mandatory=$true)]
      [String]$ContainerName,
      [Parameter(Mandatory=$true)]
      [String]$ScritpFileName,
      [Parameter(Mandatory=$true)]
      [String]$Location,
      [Parameter(Mandatory=$true)]
      [String]$ResourceGroupName,
      [Parameter(Mandatory=$false)]
      [String]$TagValue,
      [Parameter(Mandatory=$false)]
      [String]$Argument,
      [Parameter(Mandatory=$false)]
      [String]$vm_Name
    )
    
    $cseName = "CustomScriptExtension"
    $vm = Get-AzureRmVM -ResourceGroupName $ResourceGroupName -Name $VmName
    $cseExtension = $vm.Extensions | Where-Object { $_.Publisher -eq "Microsoft.Compute" -and $_.VirtualMachineExtensionType -eq "CustomScriptExtension" }
    
    # If there is an existing CustomScriptExtension, we need to use the same name for the extension
    if ($cseExtension) {
      $cseName = $cseExtension.Name
    }
    Set-AzureRmVMCustomScriptExtension -Name $cseName -Location $Location -ResourceGroupName $ResourceGroupName -VMName $VmName -StorageAccountName $StorageAccountName -ContainerName $ContainerName -FileName $ScritpFileName -Run $ScritpFileName -Argument $vm_Name
  }

  try {
    # Get the connection "AzureRunAsConnection"
    $Conn = Get-AutomationConnection -Name AzureRunAsConnection
    "Logging in to Azure..."
    Add-AzureRmAccount -ServicePrincipal -Tenant $Conn.TenantID -ApplicationId $Conn.ApplicationID -CertificateThumbprint $Conn.CertificateThumbprint
  }catch {
    if (!$servicePrincipalConnection) {
      $ErrorMessage = "Connection $connectionName not found."
      throw $ErrorMessage
    } else{
      Write-Error -Message $_.Exception
      throw $_.Exception
    }
  }

  Foreach($TagValue in $TagValues){
    $vms = Get-AzureRmResource -TagName $TagName -TagValue $TagValue | Where-Object {$_.ResourceType -like "Microsoft.Compute/virtualMachines"}
    Foreach -Parallel ($vm in $vms){
        if($Shutdown){     
            if ($($vm.Name)  -notmatch '\dSVC|OLTP|REPL|SSRS|PRPT'){
            Write-Output "Stopping $($vm.Name)";
            Stop-AzureRmVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force;
            }
        }
    }
    Foreach -Parallel ($vm in $vms){
      if($Shutdown){
        if ($($vm.Name)  -match '\dSVC|OLTP|REPL|SSRS|PRPT'){
          Write-Output "Stopping SQL Services on node  $($vm.Name)";
          Service_Start_Stop  -VmName $vm.Name -StorageAccountName 'paymentstorageaccount' -ContainerName 'paymentscontainer' -ScritpFileName 'service-start-stop.ps1' -Location 'East US' -ResourceGroupName $vm.ResourceGroupName -vm_Name $vm.Name
        }
      }
    }
   
    Foreach -Parallel ($vm in $vms){
      if($Shutdown){
        if ($($vm.Name)  -match '\dSVC|OLTP|REPL|SSRS|PRPT'){
         Write-Output "Stopping $($vm.Name)";
         Stop-AzureRmVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName -Force;
        }
      }
      else{
        Write-Output "Starting $($vm.Name)";
        Start-AzureRmVm -Name $vm.Name -ResourceGroupName $vm.ResourceGroupName;
        Do {
          $Status = ((Get-AzureRmVM -ResourceGroupName $vm.ResourceGroupName -Name $vm.Name -Status).Statuses)[1].DisplayStatus
        } Until ($Status -eq 'VM running')
      }
    }
  }
  
  if ((-Not ($Shutdown)) -and $StartServices){
    Foreach($TagValue in $TagValues) {
      $vms = Get-AzureRmResource -TagName $TagName -TagValue $TagValue | Where-Object {$_.ResourceType -like "Microsoft.Compute/virtualMachines"}
  
      "Starting Das services on Das nodes....."
      Foreach -Parallel ($vm in $vms) {
        if($Shutdown -eq $false ) {
          if(($TagName -eq 'publix' -and  $vm.Name -match 'WEBDM') -or ($vm.Name -match 'WEBDAS') -or  ($vm.Name -match 'WAP')) {
            Write-Output "Starting DAS Services on node  $($vm.Name)";
            Service_Start_Stop  -VmName $vm.Name -StorageAccountName 'paymentstorageaccount' -ContainerName 'paymentscontainer' -ScritpFileName 'service-start-stop.ps1' -Location 'East US' -ResourceGroupName $vm.ResourceGroupName -vm_Name $vm.Name
          }
        }
      }
      
      "Starting All other services on nodes...."
      Foreach -Parallel ($vm in $vms) {
        if($Shutdown -eq $false ) {
          if ($($vm.Name)  -notmatch '\dSVC|OLTP|REPL|SSRS|PRPT'){
            Write-Output "Starting Services on node  $($vm.Name)";
            Service_Start_Stop  -VmName $vm.Name -StorageAccountName 'paymentstorageaccount' -ContainerName 'paymentscontainer' -ScritpFileName 'start-service-all.ps1' -Location 'East US' -ResourceGroupName $vm.ResourceGroupName -vm_Name $vm.Name
          }
        }
      }
    }
  } else {
    Write-Output "Skipping starting services as it is not applicable/choosen for this action";
  }
}