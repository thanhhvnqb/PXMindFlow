FROM python:3.12-slim
WORKDIR /app
COPY requirements.lock .
RUN pip install --no-cache-dir -r requirements.lock
# Worktree files can be owner-only; the runtime user must own the copied code.
COPY --chown=10001:10001 . .
RUN useradd --uid 10001 --create-home mindflow
USER mindflow
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
