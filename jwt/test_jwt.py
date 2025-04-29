import os
import time
import logging
from dotenv import load_dotenv
import jwt  # Make sure to install PyJWT, not just jwt
from typing import Optional

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def load_private_key(jwt_private_key_path: str) -> bytes:
    """Load private key from file"""
    try:
        with open(jwt_private_key_path, 'rb') as key_file:
            private_key = key_file.read()
        return private_key
    except Exception as e:
        logger.critical(f"Failed to load private key: {e}")
        raise RuntimeError("Cannot generate JWT: Private key loading failed")

def generate_jwt(jwt_key_id: Optional[str] = None, private_key_path: Optional[str] = None) -> str:
    """
    Generate JWT for Alchemy API
    """
    try:
        # Load environment variables
        load_dotenv()
        
        # Get key ID from env if not provided
        jwt_key_id = jwt_key_id or os.getenv('ALCHEMY_MAINNET_KEY_ID')
        if not jwt_key_id:
            raise ValueError("JWT Key ID is required")
            
        # Get private key path if not provided
        private_key_path = private_key_path or 'pydantic_trader/private_key.pem'
        
        # Load private key
        private_key = load_private_key(private_key_path)
        
        # Current timestamp
        now = int(time.time())
        
        # JWT payload
        payload = {
            'iat': now,
            'exp': now + 600,  # 10 minutes
            'sub': 'alchemy-mainnet-price-feed'
        }
        
        # JWT headers
        headers = {
            'alg': 'RS256',
            'typ': 'JWT',
            'kid': jwt_key_id
        }
        
        try:
            # Print package version and details
            logger.info(f"JWT Package Version: {jwt.__version__}")
            logger.info(f"JWT Package Location: {jwt.__file__}")
            
            # Generate token
            token = jwt.encode(
                payload,
                private_key,
                algorithm='RS256',
                headers=headers
            )
            
            logger.info("Successfully generated JWT token")
            logger.info(f"Token: {token[:50]}...")  # Only show first 50 chars for security
            return token
            
        except AttributeError as ae:
            logger.critical(f"JWT encode function not found. Error: {ae}")
            logger.critical("This might be due to wrong JWT package. Make sure to install 'PyJWT' package.")
            raise
        except Exception as e:
            logger.critical(f"JWT encoding failed: {e}")
            raise
            
    except Exception as e:
        logger.critical(f"JWT generation failed: {e}")
        raise

if __name__ == "__main__":
    try:
        # Try generating JWT
        token = generate_jwt()
        print("\nGenerated Token (first 50 chars):", token[:50])
    except Exception as e:
        print(f"\nFailed to generate JWT: {e}") 