import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  Logger,
} from '@nestjs/common';

/** A business error with a stable code the apps translate (RFC 9457 style). */
export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message?: string,
    public readonly extra?: Record<string, unknown>,
  ) {
    super(message ?? code);
  }
}

export const Errors = {
  validation: (detail: unknown) => new AppError(400, 'VALIDATION_FAILED', 'Invalid request', { detail }),
  unauthorized: () => new AppError(401, 'UNAUTHORIZED', 'Authentication required'),
  forbidden: () => new AppError(403, 'FORBIDDEN', 'Not allowed'),
  notFound: (what: string) => new AppError(404, 'NOT_FOUND', `${what} not found`),
  conflict: (code: string, msg?: string) => new AppError(409, code, msg),
  tooMany: (code: string, retryAfterSec?: number) =>
    new AppError(429, code, 'Too many requests', retryAfterSec ? { retryAfterSec } : undefined),
};

@Catch()
export class ProblemFilter implements ExceptionFilter {
  private readonly log = new Logger('Errors');

  catch(exception: unknown, host: ArgumentsHost) {
    const reply = host.switchToHttp().getResponse();
    let status = 500;
    let code = 'INTERNAL';
    let title = 'Internal error';
    let extra: Record<string, unknown> | undefined;

    if (exception instanceof AppError) {
      status = exception.status;
      code = exception.code;
      title = exception.message;
      extra = exception.extra;
    } else if (typeof exception === 'object' && exception !== null && ['23503', '23514', '22P02'].includes(String((exception as { code?: unknown }).code))) {
      // Bad references or values that the database rejected: the request was invalid.
      status = 400;
      code = 'VALIDATION_FAILED';
      title = 'Invalid request';
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      code = status === 404 ? 'NOT_FOUND' : 'HTTP_ERROR';
      title = exception.message;
    } else {
      this.log.error(exception instanceof Error ? exception.stack : String(exception));
    }

    reply
      .status(status)
      .header('content-type', 'application/problem+json')
      .send({ type: 'about:blank', title, status, code, ...(extra ?? {}) });
  }
}
