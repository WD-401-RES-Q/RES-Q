import { initializeApp } from 'firebase/app';
import { getFirestore } from 'firebase/firestore';
import { getAuth } from 'firebase/auth';
import { getFunctions } from 'firebase/functions';

// Firebase configuration from your Flutter app
const firebaseConfig = {
  apiKey: 'AIzaSyDORrdIQgJ80ky1CmhxRqXIQuZtLmHT1wk',
  authDomain: 'res-q-93ca6.firebaseapp.com',
  projectId: 'res-q-93ca6',
  storageBucket: 'res-q-93ca6.firebasestorage.app',
  messagingSenderId: '406150939556',
  appId: '1:406150939556:web:c0f201829aeac55f7a3731',
  measurementId: 'G-CWQ5QWMFP6'
};

// Initialize Firebase
export const app = initializeApp(firebaseConfig);

// Initialize Firestore
export const db = getFirestore(app);

// Initialize Auth
export const auth = getAuth(app);

// Initialize Cloud Functions (asia-east2 region for RES-Q)
export const functions = getFunctions(app, 'asia-east2');
