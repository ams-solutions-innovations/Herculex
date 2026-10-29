/// Action errors are useful explanations; database/platform details are not UI.
String workoutActionMessage(Object error) {
  if (error is StateError) return '${error.message}';
  if (error is FormatException)
    return 'This saved plan is not supported. Refresh it and try again.';
  return 'The change could not be completed. Reopen it and try again.';
}
