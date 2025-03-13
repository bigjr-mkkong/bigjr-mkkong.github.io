// Falling Stars Effect

function createStar() {
    let star = document.createElement("div");
    star.classList.add("star");

    // Random position at top
    star.style.left = Math.random() * window.innerWidth + "px";
    star.style.top = "0px";

    // Random size for variation
    let size = Math.random() * 3 + 2;
    star.style.width = size + "px";
    star.style.height = size + "px";

    // Random fall duration
    let duration = Math.random() * 3 + 2;
    star.style.animationDuration = duration + "s";

    document.body.appendChild(star);

    // Remove star after it falls
    setTimeout(() => {
        star.remove();
    }, duration * 1000);
}

// Generate stars at random intervals
setInterval(createStar, 200);

