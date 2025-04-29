// Import the built-in fs module for reading the private key from file
const fs = require('fs');

// Import the jsonwebtoken library for creating JWTs.
const jwt = require('jsonwebtoken');

// Key Id - replace 'ENV_VAR' with your actual key ID from your provider (e.g., Alchemy)
const KEY_ID = 'ENV_VAR';

// Define a function to generate the JWT
function generateJWT() {
    // Read the private key from our 'private_key.pem' file
    const privateKey = fs.readFileSync('private_key.pem');

    // Define the options for signing the JWT
    // The "algorithm" field specifies the algorithm to use, which is 'RS256' (RSA with SHA-256)
    // This is one of the algorithms we support (others include RS384, RS512, ECDSA256, ECDSA384, ECDSA512)
    // The "expiresIn" field specifies when the token will expire, which is '10m' (10 minute) after being issued.
    // The shorter the expiration time, the more secure the token is.
    // In the "header" field we can add additional properties. In this case we're adding the "kid" filed which is the key id that is used by Alchemy to decided which public key should be used to verify the given JWT signature.
    // This should be the key id that you got from Alchemy Dashboard once you set up your key.
    const signOptions = {
        algorithm: 'RS256',
        expiresIn: '10m',
        header: {
            kid: KEY_ID,
        }
    };

    // Sign an empty payload using the private key and the sign options ( empty payload because we are not sending any additional info in the JWT )
    // The jwt.sign() function returns the JWT as a string
    const token = jwt.sign({}, privateKey, signOptions);

    // Log the newly created JWT
    console.log(token);
}

// Execute the function to generate the JWT
generateJWT();