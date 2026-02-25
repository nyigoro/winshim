Set-Variable -Name STRATEGY_DOUBLE_SLASH -Value "double-slash" -Option ReadOnly -Force
Set-Variable -Name STRATEGY_SINGLE_SLASH -Value "single-slash" -Option ReadOnly -Force
Set-Variable -Name STRATEGY_DRIVE_LETTER -Value "drive-letter" -Option ReadOnly -Force

Set-Variable -Name STRATEGY_ALL -Value @(
  $STRATEGY_DOUBLE_SLASH,
  $STRATEGY_SINGLE_SLASH,
  $STRATEGY_DRIVE_LETTER
) -Option ReadOnly -Force

# Probe order for C: workspaces preserves legacy preference.
Set-Variable -Name STRATEGY_PROBE_ORDER_C_DRIVE -Value @(
  $STRATEGY_DOUBLE_SLASH,
  $STRATEGY_SINGLE_SLASH,
  $STRATEGY_DRIVE_LETTER
) -Option ReadOnly -Force

# GitHub-hosted runners frequently place workspaces on D:, where drive-letter
# paths are the most reliable volume specification.
Set-Variable -Name STRATEGY_PROBE_ORDER_NON_C_DRIVE -Value @(
  $STRATEGY_DRIVE_LETTER,
  $STRATEGY_DOUBLE_SLASH,
  $STRATEGY_SINGLE_SLASH
) -Option ReadOnly -Force

Set-Variable -Name STRATEGY_LABELS -Value @{
  $STRATEGY_DOUBLE_SLASH = "//<drive>/"
  $STRATEGY_SINGLE_SLASH = "/<drive>/"
  $STRATEGY_DRIVE_LETTER = "<Drive>:/"
} -Option ReadOnly -Force
