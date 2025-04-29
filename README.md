# Basic JWT Generation: NodeJS
## Overview
This project demonstrates how to generate JSON Web Tokens (JWT) in Node.js using the `jsonwebtoken` package.

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
First, generate the RSA key pair (this creates the required `private_key.pem` file):
```
npm run generate-keys
```

### Generate a JWT
After generating the key pair, update the `KEY_ID` in `generateJWT.js` with your actual key ID, then run:
```
npm run generate-jwt
```

## Configuration
- The JWT is signed using the RS256 algorithm with a 10-minute expiration time
- Update the `KEY_ID` constant in `generateJWT.js` with your specific key ID

## License
MIT
