// Import the built-in crypto module for generating keys
const crypto = require('crypto');

// Import the built-in fs module for writing keys to files
const fs = require('fs');

// Define a function to generate the key pair
function generateKeyPair() {
    // Generate a new key pair using Ed25519 algorithm
    // Ed25519 is a modern, secure digital signature algorithm that offers better security
    // than RSA with smaller keys and faster operations
    const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519', {
        // Ed25519 doesn't require specifying key size as it's fixed
    });

    // Write the private key to a file named 'private_key.pem'
    fs.writeFileSync('private_key.pem', privateKey.export({
        type: 'pkcs8',
        format: 'pem'
    }));

    // Write the public key to a file named 'public_key.pem'
    fs.writeFileSync('public_key.pem', publicKey.export({
        type: 'spki',
        format: 'pem'
    }));

    // Log that the key pair was generated and saved to files
    console.log('Ed25519 key pair generated and saved to files "private_key.pem" and "public_key.pem".');
}

// Execute the function to generate the key pair
generateKeyPair();