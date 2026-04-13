importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// Firebase needs this basic initialization to run the background worker
firebase.initializeApp({
  apiKey: "AIzaSyB8z5GflH7xLhASkpWvIW2v0CP8QIM4UZs",
  projectId: "trideta-school-app-2026",
  messagingSenderId: "774050799627",
  appId: "1:774050799627:web:c0f876f565d231b85d270e"
});

const messaging = firebase.messaging();