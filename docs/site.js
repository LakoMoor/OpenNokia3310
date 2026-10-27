(() => {
  const canvas = document.querySelector('#lcd-demo');
  const context = canvas.getContext('2d');
  const buttons = document.querySelectorAll('[data-palette]');
  function draw(palette) {
    const dark = palette === 'gray' ? '#252b24' : '#27391f';
    const light = palette === 'gray' ? '#d6d9cb' : '#bfce91';
    context.fillStyle = light;
    context.fillRect(0, 0, 84, 48);
    context.fillStyle = dark;
    context.font = 'bold 7px monospace';
    context.textBaseline = 'top';
    context.fillText('MENU', 3, 3);
    context.fillRect(3, 12, 78, 1);
    context.fillRect(3, 16, 78, 9);
    context.fillStyle = light;
    context.fillText('> Phonebook', 5, 17);
    context.fillStyle = dark;
    context.fillText('  Messages', 5, 27);
    context.fillText('  Settings', 5, 37);
    buttons.forEach(button => button.setAttribute('aria-pressed', String(button.dataset.palette === palette)));
  }
  buttons.forEach(button => button.addEventListener('click', () => draw(button.dataset.palette)));
  draw('green');
})();
