FROM python:3.12-slim

WORKDIR /app

# 의존성 설치
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 앱 코드 복사
COPY app app

# 8080 포트로 FastAPI 실행
CMD ["uvicorn", "app.app:app", "--host", "0.0.0.0", "--port", "8080"]

