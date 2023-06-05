require 'telegram/bot'
require 'httpclient'
require 'json'
require 'debug'
require 'dotenv'
Dotenv.load

TOKEN = ENV['YOUR_TELEGRAM_BOT_TOKEN'] # Токен Telegram Bot API
SPEECHKIT_API_KEY = ENV['YOUR_YANDEX_SPEECH_KIT_API_KEY'] # API-ключ Яндекс Спечкит
BUCKET_NAME = ENV['YOUR_BUCKET_NAME'] # Название вашего Yandex Object Storage bucket


# Загрузка файла в Yandex Object Storage
def upload_to_object_storage(file_url)
  file_key = File.basename(file_url)
  file_data = HTTPClient.get(file_url).body
  object_storage_url = "https://storage.yandexcloud.net/#{BUCKET_NAME}/#{file_key}"

  response = HTTPClient.put(object_storage_url, body: file_data,
                                                headers: { 'Authorization' => "Bearer #{SPEECHKIT_API_KEY}",
                                                           'serviceAccountId' => 'ajef4rl3em7c8ca2pho5' })

  binding.break
  if response.code == 201
    file_key
  else
    nil
  end
end

# Получение URL файла из Yandex Object Storage
def object_storage_file_url(file_key)
  "https://storage.yandexcloud.net/#{BUCKET_NAME}/#{file_key}"
end

# Обработчик аудиосообщений
def handle_audio_message(message, bot)
  file_id = message.voice.file_id
  file_path = bot.api.get_file(file_id: file_id)['result']['file_path']
  file_url = "https://api.telegram.org/file/bot#{TOKEN}/#{file_path}"

  # Загрузка аудиофайла в Yandex Object Storage
  uploaded_file_key = upload_to_object_storage(file_url)
  #binding.break
  if uploaded_file_key
    puts "Аудиофайл успешно загружен в Yandex Object Storage. Ключ файла: #{uploaded_file_key}"

    # Получение URL загруженного файла
    file_url = object_storage_file_url(uploaded_file_key)
    puts "URL загруженного файла: #{file_url}"

    # Отправка аудиофайла на асинхронное распознавание
    response = HTTPClient.post(
      'https://transcribe.api.cloud.yandex.net/speech/stt/v2/longRunningRecognize',
      headers: {
        'Authorization' => "Api-Key #{SPEECHKIT_API_KEY}",
        'Content-Type' => 'application/json'
      },
      body: {
        config: {
          specification: {
            languageCode: 'ru-RU'
          }
        },
        audio: {
          uri: file_url
        }
      }.to_json
    )

    if response.code == 202
      task_id = response['id']
      bot.api.send_message(chat_id: message.chat.id, text: 'Задача отправлена на распознавание. Пожалуйста, подождите...')
      puts "Задача отправлена на распознавание. Task ID: #{task_id}"

      # Запуск отдельного потока для проверки статуса задачи
      Thread.new do
        loop do
          sleep 10

          # Запрос статуса задачи
          response = HTTPClient.get(
            "https://operation.api.cloud.yandex.net/operations/#{task_id}",
            headers: {
              'Authorization' => "Api-Key #{SPEECHKIT_API_KEY}",
              'Content-Type' => 'application/json'
            }
          )

          if response.code == 200
            status = response['done']
            if status
              recognized_text = response['response']['chunks'].map { |chunk| chunk['alternatives'][0]['text'] }.join(' ')
              bot.api.send_message(chat_id: message.chat.id, text: recognized_text)
              puts "Текст распознанной речи: #{recognized_text}"
              break
            end
          else
            recognized_text = 'Ошибка при запросе статуса задачи'
            bot.api.send_message(chat_id: message.chat.id, text: recognized_text)
            puts "Ошибка при запросе статуса задачи: #{response.code} - #{response['error']['message']}"
            break
          end
        end
      end
    else
      recognized_text = 'Ошибка при отправке аудиофайла на распознавание'
      bot.api.send_message(chat_id: message.chat.id, text: recognized_text)
      puts "Ошибка при отправке аудиофайла на распознавание: #{response.code} - #{response['error']['message']}"
    end
  else
    recognized_text = 'Ошибка при загрузке аудиофайла в Yandex Object Storage'
    bot.api.send_message(chat_id: message.chat.id, text: recognized_text)
    puts "Ошибка при загрузке аудиофайла в Yandex Object Storage"
  end
end


####TELEGRAM
# Обработчик команды /start
def handle_start_command(message, bot)
  text = "Привет, #{message.from.first_name}! Говори что-нибудь, и я распознаю речь."
  bot.api.send_message(chat_id: message.chat.id, text: text)
end

# Создание экземпляра Telegram бота
Telegram::Bot::Client.run(TOKEN) do |bot|
  bot.listen do |message|
    if message.text && message.text == '/start'
      handle_start_command(message, bot)
    elsif message.voice
      handle_audio_message(message, bot)
    else
      bot.api.send_message(chat_id: message.chat.id, text: "Что то пошло не так(")
    end
  end
end
