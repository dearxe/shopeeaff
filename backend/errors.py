class APIError(Exception):
    def __init__(self, status, code, message, retryable=False, retry_after=None):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message
        self.retryable = retryable
        self.retry_after = retry_after

    def detail(self):
        return {"code": self.code, "message": self.message, "retryable": self.retryable}
