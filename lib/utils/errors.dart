/// An error as a short message for the user ("Exception: " taken off).
String errorMessage(Object error) =>
    '$error'.replaceFirst('Exception: ', '');
