const express = require('express');
const bodyParser = require('body-parser');
const admin = require('firebase-admin');
const { getFirestore } = require('firebase-admin/firestore');

// TENTATIVE DE CHARGEMENT DE LA CLÉ DE SERVICE
// Sur Render, vous pourrez copier le contenu du JSON dans une variable d'environnement
let serviceAccount;
try {
    serviceAccount = require("./serviceAccountKey.json");
} catch (e) {
    console.log("serviceAccountKey.json non trouvé, utilisation des variables d'environnement.");
    serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

// Utiliser la base de données spécifiée 'transen'
const db = getFirestore('transen');
const app = express();
app.use(bodyParser.json());

// Endpoint de santé pour Render
app.get('/', (req, res) => {
    res.send('Serveur Webhook TranSen opérationnel 🚀');
});

app.post('/webhook/senepay', async (req, res) => {
    const { orderReference, status, amount } = req.body;

    console.log(`[SenePay] Webhook reçu: ${orderReference} - Status: ${status} - Montant: ${amount}`);

    if (status === 'Completed' || status === 'PAID') {
        try {
            // Extraire l'ID utilisateur de orderReference (DEP-timestamp-userId)
            const parts = orderReference.split('-');
            if (parts.length < 3) {
                console.error("Format orderReference invalide:", orderReference);
                return res.status(400).send("Format orderReference invalide");
            }
            const userId = parts[2];

            // 1. Vérifier l'idempotence (si déjà traité)
            const transactionRef = db.collection('users').doc(userId).collection('transactions');
            const existing = await transactionRef.where('description', '==', `Dépôt SenePay réussi : ${orderReference}`).get();

            if (!existing.empty) {
                console.log("Transaction déjà traitée, ignorer.");
                return res.status(200).send("OK (Déjà traité)");
            }

            // 2. Mettre à jour le solde de manière atomique
            const userRef = db.collection('users').doc(userId);
            
            await db.runTransaction(async (t) => {
                const userDoc = await t.get(userRef);
                if (!userDoc.exists) throw new Error("Utilisateur non trouvé");

                const currentBalance = userDoc.data().walletBalance || 0;
                const newBalance = currentBalance + Number(amount);

                t.update(userRef, { walletBalance: newBalance });
                
                // Ajouter à l'historique
                const newTxRef = transactionRef.doc();
                t.set(newTxRef, {
                    amount: Number(amount),
                    description: `Dépôt SenePay réussi : ${orderReference}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'deposit'
                });
            });

            // 3. Supprimer le dépôt en attente
            await db.collection('users').doc(userId).collection('pending_deposits').doc(orderReference).delete();

            console.log(`✅ Portefeuille crédité pour ${userId}: +${amount} FCFA`);
            return res.status(200).send("OK - Crédité");
        } catch (error) {
            console.error("❌ Erreur traitement webhook:", error);
            return res.status(500).send("Internal Error");
        }
    }

    res.status(200).send("Statut ignoré");
});

app.post('/webhook/payout', async (req, res) => {
    const { externalId, status, amount, internalId } = req.body;

    console.log(`[SenePay] Payout Webhook reçu: ${externalId} - Status: ${status}`);

    if (status === 'Failed' || status === 'Cancelled' || status === 'REJECTED') {
        try {
            // Extraire l'ID utilisateur de externalId (PO-timestamp-userId)
            const parts = externalId.split('-');
            if (parts.length < 3) return res.status(400).send("Format externalId invalide");
            const userId = parts[2];

            // 1. Vérifier si on a déjà remboursé (Idempotence)
            const transactionRef = db.collection('users').doc(userId).collection('transactions');
            const existing = await transactionRef.where('description', '==', `Remboursement retrait échoué : ${internalId}`).get();

            if (!existing.empty) {
                console.log("Remboursement déjà effectué.");
                return res.status(200).send("OK (Déjà remboursé)");
            }

            // 2. Recréditer le solde
            const userRef = db.collection('users').doc(userId);
            await db.runTransaction(async (t) => {
                const userDoc = await t.get(userRef);
                const currentBalance = userDoc.data().walletBalance || 0;
                t.update(userRef, { walletBalance: currentBalance + Number(amount) });
                t.set(transactionRef.doc(), {
                    amount: Number(amount),
                    description: `Remboursement retrait échoué : ${internalId}`,
                    date: admin.firestore.FieldValue.serverTimestamp(),
                    type: 'refund'
                });
            });

            console.log(`↩️ Retrait échoué remboursé pour ${userId}: +${amount} FCFA`);
            return res.status(200).send("OK - Remboursé");
        } catch (error) {
            console.error("❌ Erreur traitement payout webhook:", error);
            return res.status(500).send("Internal Error");
        }
    }

    res.status(200).send("Statut ignoré");
});

// CONFIGURATION SENEPAY
const SENEPAY_CONFIG = {
    apiKey: process.env.SENEPAY_API_KEY || 'votre_cle_pk_ici',
    apiSecret: process.env.SENEPAY_API_SECRET || 'votre_cle_sk_ici',
    baseUrl: 'https://api.sene-pay.com'
};

// Endpoint pour créer une session de paiement (Payin)
app.post('/api/payment/create-session', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/checkout/sessions`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            },
            body: JSON.stringify(req.body)
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        console.error("Erreur SenePay Session:", error);
        res.status(500).send({ error: "Erreur serveur proxy" });
    }
});

// Endpoint pour créer un retrait (Payout)
app.post('/api/payment/create-payout', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            },
            body: JSON.stringify(req.body)
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        console.error("Erreur SenePay Payout:", error);
        res.status(500).send({ error: "Erreur serveur proxy" });
    }
});

// Endpoint pour vérifier le statut d'un paiement (Payin)
app.get('/api/payment/check-status/:orderReference', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/checkout/sessions/${req.params.orderReference}`, {
            headers: {
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            }
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        res.status(500).send({ error: "Erreur status proxy" });
    }
});

// Endpoint pour vérifier le statut d'un retrait (Payout)
app.get('/api/payment/payout-status/:internalId', async (req, res) => {
    try {
        const response = await fetch(`${SENEPAY_CONFIG.baseUrl}/api/v1/payouts/${req.params.internalId}`, {
            headers: {
                'X-Api-Key': SENEPAY_CONFIG.apiKey,
                'X-Api-Secret': SENEPAY_CONFIG.apiSecret
            }
        });
        const data = await response.json();
        res.status(response.status).send(data);
    } catch (error) {
        res.status(500).send({ error: "Erreur payout status proxy" });
    }
});

const PORT = process.env.PORT || 10000;
app.listen(PORT, () => {
    console.log(`Serveur Webhook TranSen lancé sur le port ${PORT}`);
});
