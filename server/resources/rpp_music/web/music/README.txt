Положите сюда трек: join.ogg (или другое имя — тогда поправьте tracks в config.lua).
Форматы: .ogg (лучше всего), .opus, .webm. Конвертация из mp3:
  ffmpeg -i track.mp3 -c:a libvorbis -q:a 5 join.ogg
Используйте музыку, на которую у вас есть права.
