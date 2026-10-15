from pydantic import Field
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    database_url: str
    jwt_secret: str = Field(min_length=32)
    cors_origins: list[str] = ["http://localhost:8080"]


settings = Settings()
