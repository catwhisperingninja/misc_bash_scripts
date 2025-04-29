# Basic JWT Generation: NodeJS
## Overview
This project demonstrates how to generate JSON Web Tokens (JWT) in Node.js using the `jsonwebtoken` package with Ed25519 keys.

## Prerequisites
- Node.js installed
- npm installed

## Installation
1. Clone this repository
2. Install dependencies:
   ```
   npm install
   ```

## Usage

### Generate a Key Pair
First, generate the Ed25519 key pair (this creates the required `private_key.pem` file):
```
npm run generate-keys
```

### Generate a JWT
After generating the key pair, update the `KEY_ID` in `generateJWT.js` with your actual key ID, then run:
```
npm run generate-jwt
```

## Configuration
- The JWT is signed using the EdDSA algorithm with Ed25519 keys and a 10-minute expiration time
- Update the `KEY_ID` constant in `generateJWT.js` with your specific key ID

## Security Notes
- Ed25519 is a modern digital signature algorithm that offers better security than RSA with smaller keys and faster operations
- The key size is fixed for Ed25519 and offers equivalent security to RSA-3000

## License
MIT
