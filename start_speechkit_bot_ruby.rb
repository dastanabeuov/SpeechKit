# Этот бот построен и работает на плагине(сервисе) "SpeechKit" от Яндекс.

require 'telegram/bot'
require 'net/http'
require 'json'
require 'uri'
require 'dotenv'
Dotenv.load

telegram_token = ENV['YOUR_TELEGRAM_BOT_TOKEN'] # Токен Telegram Bot API

yandex_speech_key = ENV['YOUR_YANDEX_SPEECH_KIT_API_KEY'] # API-ключ Яндекс Спечкит

# Преобразование голосового сообщения в текст с помощью Yandex Speechkit
def convert_voice_to_text(voice_file_url, yandex_speech_key)
  uri = URI.parse('https://stt.api.cloud.yandex.net/speech/v1/stt:recognize')
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri.path)
  request['Authorization'] = "Api-Key #{yandex_speech_key}"
  request['Content-Type'] = 'audio/x-wav'
  request.body = Net::HTTP.get(URI(voice_file_url))

  response = http.request(request)
  json_response = JSON.parse(response.body)

  if response.code == '200'
    return json_response['result']
  else
    return 'Error: Speech recognition failed'
  end
end

# Инициализировать бот-клиент Telegram
Telegram::Bot::Client.run(telegram_token) do |bot|
  bot.listen do |message|
    if message.voice
      voice_file_id = message.voice.file_id
      voice_file = bot.api.get_file(file_id: voice_file_id)['result']
      voice_file_path = voice_file['file_path']
      voice_file_url = "https://api.telegram.org/file/bot#{telegram_token}/#{voice_file_path}"

      text = convert_voice_to_text(voice_file_url, yandex_speech_key)

      if text.empty?
        bot.api.send_message(chat_id: message.chat.id, text: "Ошибка: Не удалось распознать голосовое сообщение")
      else
        bot.api.send_message(chat_id: message.chat.id, text: text)
      end
    elsif message.text
      if message.text == '/start'
        bot.api.send_message(chat_id: message.chat.id, text: "Привет, #{message.from.first_name}! Готов к транскрибации аудио сообщения.")
      else
        bot.api.send_message(chat_id: message.chat.id, text: "Ошибка: Что-то пошло не так!")
      end
    else
      bot.api.send_message(chat_id: message.chat.id, text: "Ошибка: Другие опции в разработке.")
    end
  end
end
