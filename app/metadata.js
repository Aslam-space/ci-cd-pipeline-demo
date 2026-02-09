// app/metadata.js
fetch('/metadata.json')
  .then(response => response.json())
  .then(data => {
      document.getElementById('build-number').innerText = data.BUILD_NUMBER;
      document.getElementById('git-commit').innerText = data.GIT_COMMIT;
  });
