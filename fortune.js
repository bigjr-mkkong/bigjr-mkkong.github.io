// Fortune Cookie Logic

function setCookie(name, value, days) {
    let expires = "";
    if (days) {
        let date = new Date();
        date.setTime(date.getTime() + (days * 24 * 60 * 60 * 1000));
        expires = "; expires=" + date.toUTCString();
    }
    document.cookie = name + "=" + encodeURIComponent(value) + expires + "; path=/";
}

function getCookie(name) {
    let nameEQ = name + "=";
    let ca = document.cookie.split(';');
    for (let i = 0; i < ca.length; i++) {
        let c = ca[i].trim();
        if (c.indexOf(nameEQ) == 0) return decodeURIComponent(c.substring(nameEQ.length, c.length));
    }
    return null;
}

function getRandomFortune() {
    return fortunes[Math.floor(Math.random() * fortunes.length)]; // Picks from fortune-quotes.js
}

function crackCookie() {
    let fortune = getRandomFortune();
    setCookie("fortune", fortune, 1);

    document.getElementById("fortuneText").innerText = fortune;
    document.getElementById("fortunePopup").style.display = "block";
}

function closePopup() {
    document.getElementById("fortunePopup").style.display = "none";
}
