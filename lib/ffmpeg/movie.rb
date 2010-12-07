module FFMPEG
  class Movie
    attr_reader :path, :duration, :time, :bitrate
    attr_reader :video_stream, :video_codec, :colorspace, :resolution, :dar
    attr_reader :audio_stream, :audio_codec, :audio_sample_rate
    
    def initialize(path)
      raise Errno::ENOENT, "the file '#{path}' does not exist" unless File.exists?(path)
      
      @path = escape(path)

      stdin, stdout, stderr = Open3.popen3("ffmpeg -i '#{path}'") # Output will land in stderr
      output = stderr.read
      
      output[/Duration: (\d{2}):(\d{2}):(\d{2}\.\d{1})/]
      @duration = ($1.to_i*60*60) + ($2.to_i*60) + $3.to_f
      
      output[/start: (\d*\.\d*)/]
      @time = $1 ? $1.to_f : 0.0
      
      @duration -= @time
      
      output[/bitrate: (\d*)/]
      @bitrate = $1 ? $1.to_i : nil
      
      output[/Video: (.*)/]
      @video_stream = $1
      
      output[/Audio: (.*)/]
      @audio_stream = $1
      
      @uncertain_duration = output.include?("Estimating duration from bitrate, this may be inaccurate")
       
      if video_stream
        @video_codec, @colorspace, resolution = video_stream.split(/\s?,\s?/)
        @resolution = resolution.split(" ").first rescue nil # get rid of [PAR 1:1 DAR 16:9]
        @dar = $1 if video_stream[/DAR (\d+:\d+)/]
      end
      
      if audio_stream
        @audio_codec, audio_sample_rate, @audio_channels = audio_stream.split(/\s?,\s?/)
        @audio_sample_rate = audio_sample_rate[/\d*/].to_i
      end
      
      @invalid = @video_stream.to_s.empty? && @audio_stream.to_s.empty?
    end
    
    def valid?
      not @invalid
    end
    
    def uncertain_duration?
      @uncertain_duration
    end
    
    def width
      resolution.split("x")[0].to_i rescue nil
    end
    
    def height
      resolution.split("x")[1].to_i rescue nil
    end
    
    def calculated_aspect_ratio
      if dar
        w, h = dar.split(":")
        w.to_f / h.to_f
      else
        aspect = width.to_f / height.to_f
        aspect.nan? ? nil : aspect
      end
    end
    
    def size
      File.size(@path)
    end
    
    def audio_channels
      return @audio_channels[/\d*/].to_i if @audio_channels["channels"]
      return 1 if @audio_channels["mono"]
      return 2 if @audio_channels["stereo"]
    end
    
    def frame_rate
      video_stream[/(\d*\.?\d*)\s?fps/] ? $1.to_f : nil
    end
    
    def transcode(output_file, options = EncodingOptions.new, transcoder_options = {}, &block)
      Transcoder.new(self, output_file, options, transcoder_options).run &block
    end
    
    protected
    def escape(path)
      map  =  { '\\' => '\\\\', '</' => '<\/', "\r\n" => '\n', "\n" => '\n', "\r" => '\n', '"' => '\\"', "'" => "\\'" }
      path.gsub(/(\\|<\/|\r\n|[\n\r"'])/) { map[$1] }
    end
  end
end
