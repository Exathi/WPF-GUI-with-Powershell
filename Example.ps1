#Remember to add the below two assemblies and dot source this file since powershell parses classes before add-types
Add-Type -AssemblyName presentationframework, presentationcore

function New-InitialSessionState {
	<#
		.SYNOPSIS
			Creates a default session while also adding user functions and user variables to be used in a new runspace
	#>
	[CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.InitialSessionState])]
	param(
		[Parameter()]
		[System.Collections.Generic.List[String]]$FunctionNames,
		[Parameter()]
		[System.Collections.Generic.List[String]]$VariableNames
	)

	process{

		# Create an initial session state object required for runspaces
		# CreateDefault allows default cmdlets to be used without being explicitly added in the runspace
		$initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

		# Add custom functions to the Session State to be added into a runspace
		foreach( $functionName in $FunctionNames ) {
			$functionDefinition = Get-Content Function:\$functionName -ErrorAction 'Stop'
			$sessionStateFunction = New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry -ArgumentList $functionName, $functionDefinition
			$initialSessionState.Commands.Add($sessionStateFunction)
		}

		# Add variables to the Session State to be added into a runspace
		foreach( $variableName in $VariableNames ) {
			$var = Get-Variable $variableName
			$runspaceVariable = New-object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList $var.name, $var.value, $null
			$initialSessionState.Variables.Add($runspaceVariable)
		}

		$initialSessionState
	}
}

function New-RunspacePool {
    <#
		.SYNOPSIS
			Creates a RunspacePool
	#>
	[CmdletBinding()]
    [OutputType([System.Management.Automation.Runspaces.RunspacePool])]
	param(
		[Parameter()]
		[InitialSessionState]$InitialSessionState,
		[Parameter()]
		[Int]$ThreadLimit = $([Int]$env:NUMBER_OF_PROCESSORS + 1),
		[Parameter(
			HelpMessage = 'Use STA on any thread that creates UI or when working with single thread COM Objects.'
		)]
		[ValidateSet("STA", "MTA", "Unknown")]
		[String]$ApartmentState = "STA",
		[Parameter()]
		[ValidateSet("Default", "ReuseThread", "UseCurrentThread", "UseNewThread")]
		[String]$ThreadOptions = "ReuseThread"
	)

	process {
		$runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $ThreadLimit, $InitialSessionState, $Host)
		$runspacePool.ApartmentState = $ApartmentState
		$runspacePool.ThreadOptions = $ThreadOptions
		$runspacePool.Open()
		$runspacePool
	}
}

function New-WPFWindow {
    [CmdletBinding(DefaultParameterSetName = 'HereString')]
    param (
        [Parameter(Mandatory, ParameterSetName = 'HereString' )]
        [string]$Xaml,

        [Parameter(Mandatory, ParameterSetName = 'Path')]
        [ValidateScript({ Test-Path $_ })]
        [System.IO.FileSystemInfo]$Path
    )

    if ($Path) {
        $Xaml = Get-Content -Path $Path
    }

    #Use the dedicated wpf xaml reader rather than the xmlreader.
    $window = [System.Windows.Markup.XamlReader]::Parse($Xaml)
    $window
}


# Powershell does not like classes with whitespace or comments in place of whitespace if copied and pasted in the console.
# Since the interface System.Windows.Input.ICommand methods Execute and CanExecute require parameters, we will keep it that way.
class RelayCommandBase : System.Windows.Input.ICommand {
    add_CanExecuteChanged([EventHandler] $value) {
        [System.Windows.Input.CommandManager]::add_RequerySuggested($value)
        Write-Debug "$value added"
    }

    remove_CanExecuteChanged([EventHandler] $value) {
        [System.Windows.Input.CommandManager]::remove_RequerySuggested($value)
        Write-Debug "$value removed"
    }

    # Invoke does not take a $null parameter so we wrap $null in an array for all cases
    # Providing the original method with $null will work, invoking with $null will not because invoke() provides arguments not parameters.
    # Arguments cannot be explicitly $null since they're optional
    # Maybe create delegate instead
    [bool]CanExecute([object]$commandParameter) {
        Write-Debug 'RelayCommandBase.CanExecute ran'
        if ($null -eq $this._canExecute) { return $true }
        return $this._canExecute.Invoke(@($commandParameter))
    }

    [void]Execute([object]$commandParameter) {
        try {
            $this._execute.Invoke(@($commandParameter))
        } catch {
            Write-Error "Error handling RelayCommandBase.Execute: $_"
        }
    }

    hidden [System.Management.Automation.PSMethod]$_execute
    hidden [System.Management.Automation.PSMethod]$_canExecute

    RelayCommandBase($Execute, $CanExecute) {
        $this.Init($Execute, $CanExecute)
    }

    RelayCommandBase($Execute) {
        $this.Init($Execute, $null)
    }

    RelayCommandBase() {}

    hidden Init($Execute, $CanExecute) {
        if ($null -eq $Execute) { throw 'RelayCommandBase.Execute is null. Supply a valid method.' }
        $this._execute = $Execute
        Write-Debug -Message $this._execute.ToString()

        $this._canExecute = $CanExecute
        if ($null -ne $this._canExecute) {
            Write-Debug -Message $this._canExecute.ToString()
        }
    }
}


# Support for parameterless PSMethods
# Doesn't seem clean
class RelayCommand : RelayCommandBase {
    [bool]CanExecute([object]$commandParameter) {
        if ($null -eq $this._canExecute) { return $true }
        # CanExecute is inefficient.
        # Write-Debug 'RelayCommand.CanExecute ran'
        if ($this._canExecuteCount -eq 1) { return $this._canExecute.Invoke($commandParameter) }
        else { return $this._canExecute.Invoke() }
    }

    [void]Execute([object]$commandParameter) {
        try {
            if ($this._executeCount -eq 1) { $this._execute.Invoke($commandParameter) }
            else { $this._execute.Invoke() }
        } catch {
            Write-Error "Error handling RelayCommand.Execute: $_"
        }
    }

    hidden [int]$_executeCount
    hidden [int]$_canExecuteCount

    #RelayCommand($Execute, $CanExecute) : base($Execute, $CanExecute) { # use default parameterless constructor to avoid calls to Init in this and the base class
    RelayCommand($Execute, $CanExecute) {
        $this.Init($Execute, $CanExecute)
    }

    RelayCommand($Execute) {
        $this.Init($Execute, $null)
    }

    hidden Init($Execute, $CanExecute) {
        if ($null -eq $Execute) { throw 'RelayCommand.Execute is null. Supply a valid method.' }
        $this._executeCount = $this.GetParameterCount($Execute)
        $this._execute = $Execute
        Write-Debug -Message $this._execute.ToString()

        $this._canExecute = $CanExecute
        if ($null -ne $this._canExecute) {
            $this._canExecuteCount = $this.GetParameterCount($CanExecute)
            Write-Debug -Message $this._canExecute.ToString()
        }
    }

    hidden [int]GetParameterCount([System.Management.Automation.PSMethod]$Method) {
        # Alternatively pass the viewmodel into RelayCommand
        # $ViewModel.GetType().GetMethod($PSMethod.Name).GetParameters().Count
        $param = $Method.OverloadDefinitions[0].Split('(').Split(')')[1]
        if ([string]::IsNullOrWhiteSpace($param)) { return 0 }

        $paramCount = $param.Split(',').Count
        Write-Debug "$($Method.OverloadDefinitions[0].Split('(').Split(')')[1].Split(',')) relaycommand param count"
        if ($paramCount -gt 1) { throw "RelayCommand expected parameter count 0 or 1. Found PSMethod with count $paramCount" }
        return $paramCount
    }
}


class DelegateCommand : System.Windows.Input.ICommand {
    add_CanExecuteChanged([EventHandler] $value) {
        [System.Windows.Input.CommandManager]::add_RequerySuggested($value)
        Write-Debug "$value added"
    }

    remove_CanExecuteChanged([EventHandler] $value) {
        [System.Windows.Input.CommandManager]::remove_RequerySuggested($value)
        Write-Debug "$value removed"
    }

    # Delegate takes $null unlike invoking the PSMethod where it passes as arguments
    [bool]CanExecute([object]$commandParameter) {
        #Write-Debug 'DelegateCommand.CanExecute ran'
        if ($null -eq $this._canExecute) { return $true }
        return $this._canExecute.Invoke($commandParameter)
    }

    [void]Execute([object]$commandParameter) {
        try {
            $this._execute.Invoke($commandParameter)
        } catch {
            Write-Error "Error handling DelegateCommand.Execute: $_"
        }
    }

    hidden [System.Delegate]$_execute
    hidden [System.Delegate]$_canExecute

    DelegateCommand($Execute, $CanExecute) {
        $this.Init($Execute, $CanExecute)
    }

    DelegateCommand($Execute) {
        $this.Init($Execute, $null)
    }

    DelegateCommand() {}

    hidden Init($Execute, $CanExecute) {
        if ($null -eq $Execute) { throw 'DelegateCommand.Execute is null. Supply a valid method.' }
        $this._execute = $Execute
        Write-Debug -Message $this._execute.ToString()

        $this._canExecute = $CanExecute
        if ($null -ne $this._canExecute) {
            Write-Debug -Message $this._canExecute.ToString()
        }
    }
}


class ViewModelBase : ComponentModel.INotifyPropertyChanged {
    hidden [ComponentModel.PropertyChangedEventHandler] $_propertyChanged

    [void]add_PropertyChanged([ComponentModel.PropertyChangedEventHandler] $value) {
        $this._propertyChanged = [Delegate]::Combine($this._propertyChanged, $value)
    }

    [void]remove_PropertyChanged([ComponentModel.PropertyChangedEventHandler] $value) {
        $this._propertyChanged = [Delegate]::Remove($this._propertyChanged, $value)
    }

    [void]OnPropertyChanged([string] $propertyName) {
        Write-Debug "Notified change of property '$propertyName'."
        #$this._propertyChanged.Invoke($this, $propertyName) # Why does this accepting a string also work?
        #$this._PropertyChanged.Invoke($this, (New-Object PropertyChangedEventArgs $propertyName))
        # There are cases where it is null, which shoots a non terminating error. I forget when I ran into it.
        if ($null -ne $this._PropertyChanged) {
            $this._PropertyChanged.Invoke($this, [System.ComponentModel.PropertyChangedEventArgs]::new($propertyName))
            Write-Debug "not null '$propertyName'."
        }

    }

    [void]Init([string] $propertyName) {
        $setter = [ScriptBlock]::Create("
            param(`$value)
            `$this.'_$propertyName' = `$value
            `$this.OnPropertyChanged('_$propertyName')
        ")

        $getter = [ScriptBlock]::Create("`$this.'_$propertyName'")
        Write-Debug $setter.ToString()
        Write-Debug $getter.ToString()

        $this | Add-Member -MemberType ScriptProperty -Name "$propertyName" -Value $getter -SecondValue $setter
    }

    [Windows.Input.ICommand]NewCommand(
        [System.Management.Automation.PSMethod]$Execute,
        [System.Management.Automation.PSMethod]$CanExecute
    ) {
        return [RelayCommandBase]::new($Execute, $CanExecute)
    }

    [Windows.Input.ICommand]NewCommand(
        [System.Management.Automation.PSMethod]$Execute
    ) {
        return [RelayCommandBase]::new($Execute)
    }

    # Experimental - Probably not needed in PowerShell 7.2+
    [Windows.Input.ICommand]NewDelegate(
        [System.Management.Automation.PSMethod]$Execute,
        [System.Management.Automation.PSMethod]$CanExecute
    ) {
        #$delegateExecute = $this.GetType().GetMethod($Execute.Name).CreateDelegate([action[object]], $this)
        #$delegateCanExecute = $this.GetType().GetMethod($CanExecute.Name).CreateDelegate([func[object,bool]], $this)
        $e = $this.BuildDelegate($Execute)
        $ce = $this.BuildDelegate($CanExecute)
        return [DelegateCommand]::new($e, $ce)
    }

    [Windows.Input.ICommand]NewDelegate(
        [System.Management.Automation.PSMethod]$Execute
    ) {
        $e = $this.BuildDelegate($Execute)
        return [DelegateCommand]::new($e)
    }

    hidden [System.Delegate]BuildDelegate([System.Management.Automation.PSMethod]$Method) {
        $typeMethod = $this.GetType().GetMethod($Method.Name)
        $returnType = $typeMethod.ReturnType.Name
        if ($returnType -eq 'Void') {
            $delegateString = 'Action'
            $delegateReturnParam = ']'
        } else {
            $delegateString = 'Func'
            $delegateReturnParam = ",$returnType]"
        }

        $delegateParameters = $this.GetType().GetMethod($typeMethod.Name).GetParameters()
        if ($delegateParameters.Count -ge 1) {
            $delegateString += '['
        }

        $paramString = ''
        foreach ($p in $delegateParameters) {
            $paramString += "$($p.ParameterType.Name),"
        }

        if ($paramString.Length -gt 0) {
            $paramString = $paramString.Substring(0, $paramString.Length - 1)
        } else {
            $delegateReturnParam = "[$returnType]"
            if ($returnType -eq 'Void') { $delegateReturnParam = '' }
        }

        $paramString += "$delegateReturnParam"
        $delegateString += "$paramString"
        Write-Debug "$delegateString"
        return $typeMethod.CreateDelegate(($delegateString -as [type]), $this)
    }

}


class MainWindowViewModel : ViewModelBase {
    [string]$TextBoxText
    [int]$_TextBlockText
    [string]$NoParameterContent = 'No Parameter'
    [string]$ParameterContent = 'Parameter'
    [System.Windows.Input.ICommand]$TestCommand
    [System.Windows.Input.ICommand]$TestBackgroundCommand

    # Turn into cmdlet instead?
    hidden static [void]Init([string] $propertyName) {
        $setter = [ScriptBlock]::Create("
            param(`$value)
            `$this.'_$propertyName' = `$value
            `$this.OnPropertyChanged('_$propertyName')
        ")

        $getter = [ScriptBlock]::Create("`$this.'_$propertyName'")
        Write-Debug $setter.ToString()
        Write-Debug $getter.ToString()

        Update-TypeData -TypeName 'MainWindowViewModel' -MemberName $propertyName -MemberType ScriptProperty -Value $getter -SecondValue $setter
    }

    # This runs once and updates future types of this class in this scope will have the property. Other runspaces will need to load the class and initialize it.
    # Don't need to do it this way since we're only going to need one viewmodel.
    # For curosity / my first actual static method + constructor / demo purposes
    static MainWindowViewModel() {
        [MainWindowViewModel]::Init('TextBlockText')
    }

    MainWindowViewModel() {
        $this.TestCommand = $this.NewDelegate(
            $this.UpdateTextBlock,
            $this.CanUpdateTextBlock
        )
        $this.TestBackgroundCommand = $this.NewDelegate(
            $this.BackgroundCommand,
            $this.CanBackgroundCountCommand
        )
        # $this.Init('TextBlockText')
    }

    [int]$i
    [void]ExtractedMethod([int]$i) {
        $this.i += $i
        $this.TextBlockText += $i # Allowed since TextBlockText is added by Add-Member/Update-TypeData in which the set method raises OnPropertyChanged
        Write-Debug $i
    }

    [void]UpdateTextBlock([object]$RelayCommandParameter) {
        $testParameter = 1

        $message = "TextBoxText is '$($this.TextBoxText)'
Command Parameter is '$RelayCommandParameter'
If Command Parameter is null then $testParameter is used
OK To add TextBoxText
Cancel to add Command Parameter"

        $result = Show-MessageBox -Message $message

        if ($null -ne $RelayCommandParameter) {
            $testParameter = $RelayCommandParameter
        }

        if ($result -eq 'OK') {
            $value = $this.TextBoxText
        } else {
            $value = $testParameter
        }

        $this.ExtractedMethod($value)
    }

    [bool]CanUpdateTextBlock([object]$RelayCommandParameter) {
        return (-not [string]::IsNullOrWhiteSpace($this.TextBoxText))
    }

    # Todo - move to ViewModelBase
    [void]BackgroundCommand([object]$RelayCommandParameter) {
        #$this.IsBackgroundFree = $false
        $this.CurrentBackgroundCount += 1
        $this.OnPropertyChanged('CurrentBackgroundCount')
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke(
            {
                $ps = [powershell]::Create()
                # Class automagically knows $syncHash // I don't think this is clean // What if you had more viewmodels, those shouldn't be spinning up their own syncHashes...
                $ps.RunspacePool = $script:syncHash.RSPool
                $sb = {
                    function Show-MessageBox {
                        [CmdletBinding()]
                        param(
                            [Parameter(Mandatory)]
                            [string]$Message,
                            [string]$Title = 'Test',
                            [string]$Button = 'OkCancel',
                            [string]$Icon = 'Information'
                        )
                        [System.Windows.MessageBox]::Show("$Message", $Title, $Button, $Icon)
                    }
                    Start-Sleep -Seconds 5
                    # Works with Add-Member. Doesn't work with Update-TypeData - UNLESS class is new'ed up in a different PowerShell + RunspacePool that also knows its definition
                    $syncHash.This.TextBlockText += 5
                    #Show-MessageBox "$($syncHash.This.IsBackgroundFree)"
                    #$syncHash.This.IsBackgroundFree = $true
                    #Show-MessageBox "$($syncHash.This.IsBackgroundFree)"
                    $syncHash.This.CurrentBackgroundCount -= 1
                    $syncHash.This.OnPropertyChanged('CurrentBackgroundCount')
                    $syncHash.This.RefreshAllButtons()
                    #$hash.This.OnPropertyChanged('_TextBlockText')
                    #Show-MessageBox "err: $($Error[0])"
                    #Show-MessageBox "$($syncHash.This.GetType().GetMembers().Name)" #add Show-MessageBox to sessionstate so you don't need  to redefine it
                }
                $null = $ps.AddScript($sb)
                $ps.BeginInvoke()
                Write-Debug 'begin'
            }
        )
    }

    [bool]$IsBackgroundFree = $true
    [bool]CanBackgroundCommand([object]$RelayCommandParameter) {
        return $this.IsBackgroundFree
    }

    [int]$CurrentBackgroundCount = 0
    [bool]CanBackgroundCountCommand([object]$RelayCommandParameter) {
        return ($this.CurrentBackgroundCount -lt 5)
    }

    # REQUIRED fails to dispatch otherwise. The runspaces use their own dispatcher? Doesn't work even when using the dispatcher from syncHash.Window.Dispatcher
    $localDispatcher = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
    [void]RefreshAllButtons(){
        $this.localDispatcher.Invoke({[System.Windows.Input.CommandManager]::InvalidateRequerySuggested()})
    }
}

function Show-MessageBox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,
        [string]$Title = 'Test',
        [ValidateSet('OK','OKCancel','AbortRetryIgnore','YesNoCancel','YesNo','RetryCancel')]
        [string]$Button = 'OkCancel',
        [ValidateSet('None','Hand','Error','Stop','Question','Exclamation','Warning','Asterisk','Information')]
        [string]$Icon = 'Information'
    )
    [System.Windows.MessageBox]::Show("$Message", $Title, $Button, $Icon)
}


$Xaml = '<Window x:Class="System.Windows.Window"
x:Name="MainWindow"
xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
xmlns:local="clr-namespace:;assembly="
mc:Ignorable="d"
Title="Minimal Example" Width="300" Height="250"
WindowStartupLocation="CenterScreen">
<!--
    <Window.DataContext>
        <local:MainWindowViewModel />
    </Window.DataContext>
-->
    <Grid>
        <StackPanel Margin="5">
            <!-- TextBox bound property does not update until textbox focus is lost. Use UpdateSourceTrigger=PropertyChanged to update as typed -->
            <TextBox x:Name="TextBox1" Text="{Binding TextBoxText, UpdateSourceTrigger=PropertyChanged}" MinHeight="30" />
            <TextBlock x:Name="TextBlock1" Text="{Binding _TextBlockText}" MinHeight="30" />
            <Button
                Content="{Binding NoParameterContent}"
                Command="{Binding TestCommand}" />
            <Button
                Content="{Binding ParameterContent}"
                Command="{Binding TestCommand}"
                CommandParameter="3" />
            <TextBlock Text="Current Background Tasks" MinHeight="30" />
            <TextBlock Text="{Binding CurrentBackgroundCount}" MinHeight="30" />
            <Button
                Content="Background Command"
                Command="{Binding TestBackgroundCommand}" />
        </StackPanel>
    </Grid>
</Window>
' #-creplace 'clr-namespace:;assembly=', "`$0$([MainWindowViewModel].Assembly.FullName)"
# BLACK MAGIC. Hard coding the FullName in the xaml does not work even after loading the ps1 file.
# If any edits, the console must be reset because the class/assembly stays loaded with the old viewmodel
# DataContext can be loaded in Xaml
# https://gist.github.com/nikonthethird/4e410ac3c04ea6633043a5cb7be1d717





# $async = $window.Dispatcher.InvokeAsync(
#     { $null = $window.ShowDialog() }
# )
# $null = $async.Wait()
