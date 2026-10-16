# encoding: UTF-8
# =============================================================================
# Конвертер текстур - Texture Converter
# Версия: 3.2
# Автор: Antoñŷ
# Файл: selftest.rb (проверка tc_native.so, в rbz не входит)
#
# Задача: проверить собранный tc_native.so до установки в плагин. Запуск в
# Ruby Console SketchUp (Окно > Консоль Ruby) или обычным ruby на той же ОС:
#   load 'C:/путь/dist/native/selftest.rb'   (или положите рядом с tc_native.so)
#   TCSelfTest.run('C:/путь/dist/native/tc_native.so')
#   TCSelfTest.run('C:/путь/dist/native/tc_native.so', 'C:/путь/к/картинке.png')
# Второй аргумент (PNG или JPG) проверяет настоящий путь плагина в SketchUp:
# Sketchup::ImageRep#data, порядок каналов BGRA, stride.
# =============================================================================
module TCSelfTest
  def self.win?
    defined?(Sketchup) && Sketchup.respond_to?(:platform) ? Sketchup.platform == :platform_win : false
  end

  def self.order
    win? ? 'bgr' : 'rgb'
  end

  # Синтетическая картинка RGBA: плавный градиент, слева 10 колонок полностью прозрачны
  def self.synth(w, h)
    s = String.new(encoding: Encoding::BINARY)
    h.times { |y| w.times { |x| s << [x * 4, y * 5, 90, x < 10 ? 0 : 255].pack('C4') } }
    s
  end

  def self.swap_rb(s, bytespp)
    o = s.dup
    (s.bytesize / bytespp).times do |i|
      o.setbyte(i * bytespp, s.getbyte(i * bytespp + 2))
      o.setbyte(i * bytespp + 2, s.getbyte(i * bytespp))
    end
    o
  end

  # Максимальное отклонение RGB только у непрозрачных пикселей и совпадение альфы
  def self.compare(src_rgba, got_rgba)
    dmax = 0
    alpha_ok = true
    (src_rgba.bytesize / 4).times do |i|
      alpha_ok &&= src_rgba.getbyte(i * 4 + 3) == got_rgba.getbyte(i * 4 + 3)
      next if src_rgba.getbyte(i * 4 + 3) == 0
      3.times { |c| d = (src_rgba.getbyte(i * 4 + c) - got_rgba.getbyte(i * 4 + c)).abs; dmax = d if d > dmax }
    end
    [dmax, alpha_ok]
  end

  def self.run(so_path, image_path = nil)
    ok = true
    require so_path
    m = TextureConverter::NativeCodecs
    puts "ABI=#{m::ABI} (ожидается 2)"
    puts "читает: #{m.features.join(', ')}; пишет: #{m.encoders.join(', ')}"
    m.versions.each { |k, v| puts "  #{k}: #{v}" }
    %w[webp avif].each do |id|
      unless m.features.include?(id) && m.encoders.include?(id)
        puts "ОШИБКА: #{id} не собран для чтения и записи"
        ok = false
        next
      end
      w, h = 64, 48
      src = synth(w, h)
      q = id == 'webp' ? 90 : 80
      t = Time.now
      file = m.encode(id, w, h, 32, w * 4, 'rgb', src, q)
      _, _, got = m.decode(id, file)
      dmax, a_ok = compare(src, got)
      puts format('%s: rgba 64x48, файл %d Б, %.2f с, откл. RGB %d, альфа точно: %s', id, file.bytesize, Time.now - t, dmax, a_ok)
      ok &&= a_ok && dmax <= 12
      # тот же результат при порядке bgr
      file2 = m.encode(id, w, h, 32, w * 4, 'bgr', swap_rb(src, 4), q)
      same = m.decode(id, file2)[2] == got
      puts "#{id}: порядок bgr даёт тот же результат: #{same}"
      ok &&= same
    end
    ok &&= run_imagerep(m, image_path) if image_path
    puts(ok ? 'ИТОГ: всё в порядке' : 'ИТОГ: ЕСТЬ ОШИБКИ')
    ok
  rescue StandardError, ScriptError => e
    puts "ОШИБКА: #{e.class}: #{e.message}"
    false
  end

  # Реальный путь плагина: ImageRep#data, порядок каналов платформы, stride
  def self.run_imagerep(m, path)
    unless defined?(Sketchup::ImageRep)
      puts 'ImageRep недоступен (запуск вне SketchUp), проверка файла пропущена'
      return true
    end
    rep = Sketchup::ImageRep.new
    rep.load_file(path)
    data = rep.data
    w, h, bpp = rep.width, rep.height, rep.bits_per_pixel
    stride = data.bytesize / h
    puts "ImageRep: #{w}x#{h}, #{bpp} бит, row_padding=#{rep.row_padding}, stride=#{stride}, порядок=#{order}"
    good = true
    %w[webp avif].each do |id|
      t = Time.now
      file = m.encode(id, w, h, bpp, stride, order, data, id == 'webp' ? 90 : 80)
      gw, gh, got = m.decode(id, file)
      puts format('  %s: файл %d Б, %.2f с, размер после чтения %dx%d', id, file.bytesize, Time.now - t, gw, gh)
      good &&= gw == w && gh == h
      # сверка цвета центрального пикселя с ImageRep (в RGBA)
      bytespp = bpp / 8
      off = (h / 2) * stride + (w / 2) * bytespp
      px = data.byteslice(off, bytespp).bytes
      px = px.values_at(2, 1, 0, *(bytespp == 4 ? [3] : [])) if order == 'bgr'
      gp = got.byteslice(((h / 2) * w + w / 2) * 4, 4).bytes
      puts "  центр: ImageRep(RGB)=#{px[0, 3].inspect}, после #{id}=#{gp[0, 3].inspect}"
    end
    good
  end
end
