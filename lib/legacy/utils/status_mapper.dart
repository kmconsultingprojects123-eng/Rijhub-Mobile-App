class StatusMapper {
  static const Map<int, String> _successLabels = {
    200: 'Success! Everything looks good.',
    201: 'Success! Your new entry has been saved.',
    202: 'Request received. We\'re processing it now.',
    204: 'Action completed successfully.',
  };

  static const Map<int, String> _errorLabels = {
    301: 'This resource has moved. Redirecting you...',
    304: 'You\'re already looking at the latest version.',
    308: 'This resource has moved. Redirecting you...',
    400: 'We couldn\'t process that info. Please check your input.',
    401: 'Your session has expired. Please log in again.',
    403: 'You don\'t have permission to access this.',
    404: 'We can\'t find what you\'re looking for.',
    405: 'This action isn\'t allowed right now.',
    408: 'Connection timed out. Please try again.',
    409: 'This already exists or there\'s a data conflict.',
    410: 'This item is no longer available.',
    413: 'The file you\'re trying to send is too big.',
    415: 'This file type isn\'t supported.',
    422: 'Please fix the errors in the form and try again.',
    429: 'Too many requests! Please slow down a bit.',
    500: 'Something went wrong on our end. We\'re fixing it!',
    502: 'The server is temporarily unreachable.',
    503: 'System maintenance in progress. Back soon!',
    504: 'The server took too long to respond.',
  };

  static bool isSuccess(int? statusCode) =>
      statusCode != null && statusCode >= 200 && statusCode < 300;

  static bool isRedirect(int? statusCode) =>
      statusCode != null && statusCode >= 300 && statusCode < 400;

  static bool isError(int? statusCode) =>
      statusCode != null && statusCode >= 400;

  static String getLabel(int statusCode) {
    return _successLabels[statusCode] ?? 'Done!';
  }

  static String getError(
    int? statusCode, {
    String? networkError,
  }) {
    if (networkError != null && networkError.trim().isNotEmpty) {
      return networkError.trim();
    }
    if (statusCode == null) {
      return 'An unexpected error occurred.';
    }
    return _errorLabels[statusCode] ?? _unknownStatus(statusCode);
  }

  static String getMessage(
    int? statusCode, {
    String? networkError,
  }) {
    if (networkError != null && networkError.trim().isNotEmpty) {
      return networkError.trim();
    }
    if (statusCode == null) {
      return 'An unexpected error occurred.';
    }
    if (isSuccess(statusCode)) {
      return getLabel(statusCode);
    }
    return _errorLabels[statusCode] ?? _unknownStatus(statusCode);
  }

  static String _unknownStatus(int statusCode) {
    return 'Error $statusCode: Our robots are confused, but they\'re working on it!';
  }
}
