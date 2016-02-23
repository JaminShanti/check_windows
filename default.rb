#
# Cookbook Name:: check_windows
# Recipe:: default
#
# Copyright 2015
#
#



directory 'C:\\DevOps' do
  owner 'x3administrator'
  group 'administrator'
  mode '0755'
  action :create
end

# creating Check_WindowsNode.ps1
cookbook_file 'C:\devops\Check_WindowsNode.ps1' do
  owner 'x3administrator'
  group 'administrator'
  mode '0755'
  source 'Check_WindowsNode.ps1'
  action :create
end

#create schedule job
powershell_script 'Create Scheduled Job' do
  cwd 'C:\\devops'
  code 'Register-ScheduledJob -Name "Check_Windows" -ScriptBlock { powershell -noprofile -executionpolicy bypass -command "& {C:\\devops\\Check_WindowsNode.ps1 >> C:\\devops\\Check_WindowsNode_Log.log 2>&1}" } -Trigger @{Frequency="Daily";At="12:00AM"}; Add-JobTrigger -Trigger  @{Frequency="Daily";At="4:00AM"} -Name Check_Windows;Add-JobTrigger -Trigger  @{Frequency="Daily";At="8:00AM"} -Name Check_Windows; Add-JobTrigger -Trigger  @{Frequency="Daily";At="12:00PM"}  -Name Check_Windows; Add-JobTrigger -Trigger  @{Frequency="Daily";At="4:00PM"}  -Name Check_Windows;  Add-JobTrigger -Trigger  @{Frequency="Daily";At="8:00PM"} -Name Check_Windows'
  guard_interpreter :powershell_script
  not_if  '!!$(Get-ScheduledJob -Name Check_Windows -ErrorAction SilentlyContinue)'
  only_if do File.exist?('C:\\devops\\Check_WindowsNode.ps1')end
end

