from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    SECRET_KEY: str = "changeme-use-env"
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60

    # Database — auto-detected:
    #   Local:      sqlite+aiosqlite:///./sahjanand.db
    #   Production: Render injects DATABASE_URL as postgres://...
    DATABASE_URL: str = "sqlite+aiosqlite:///./sahjanand.db"

    # Cloudinary (image storage)
    CLOUDINARY_CLOUD_NAME: str = ""
    CLOUDINARY_API_KEY: str = ""
    CLOUDINARY_API_SECRET: str = ""

    APP_NAME: str = "Sahjanand"
    FRONTEND_URL: str = "http://127.0.0.1:5500"

    # Production frontend URL (set in Render env vars)
    PRODUCTION_URL: str = ""

    @property
    def async_database_url(self) -> str:
        """
        Render provides DATABASE_URL as postgres://...
        SQLAlchemy asyncpg requires postgresql+asyncpg://...
        This property fixes the URL automatically.
        """
        url = self.DATABASE_URL
        if url.startswith("postgres://"):
            url = url.replace("postgres://", "postgresql+asyncpg://", 1)
        elif url.startswith("postgresql://") and "+asyncpg" not in url:
            url = url.replace("postgresql://", "postgresql+asyncpg://", 1)
        return url

    class Config:
        env_file = ".env"


@lru_cache()
def get_settings() -> Settings:
    return Settings()
