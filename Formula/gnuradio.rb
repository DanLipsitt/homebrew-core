class Gnuradio < Formula
  desc "SDK providing the signal processing runtime and processing blocks"
  homepage "https://gnuradio.org/"
  url "https://gnuradio.org/releases/gnuradio/gnuradio-3.7.11.tar.gz"
  sha256 "87d9ba3183858efdbb237add3f9de40f7d65f25e16904a9bc8d764a7287252d4"
  revision 4
  head "https://github.com/gnuradio/gnuradio.git"

  bottle do
    sha256 "ffc99690ce3cc34d2a072351a6650c6ec3216f6bb91a27d9c95f0cd56fb242d6" => :high_sierra
    sha256 "23502002ce6da05a78aa254c5034c3dfb182dfe1cc70c9a0f40afab03663cfb6" => :sierra
    sha256 "b83941d5f6486c6f931e667979dc6dc893483cfea54789a7ee764137e0ce8fba" => :el_capitan
  end

  option "without-python@2", "Build without python support"

  deprecated_option "without-python" => "without-python@2"

  depends_on "cmake" => :build
  depends_on "pkg-config" => :build
  depends_on "python@2" => :recommended
  depends_on "boost"
  depends_on "fftw"
  depends_on "gsl"
  depends_on "zeromq"

  if build.with? "python@2"
    depends_on "swig" => :build
    depends_on "numpy"
  end

  # For documentation
  depends_on "doxygen" => [:build, :optional]
  depends_on "sphinx-doc" => [:build, :optional]

  depends_on "uhd" => :recommended
  depends_on "sdl" => :optional
  depends_on "jack" => :optional
  depends_on "portaudio" => :recommended
  depends_on "pygtk" => :optional
  depends_on "wxpython" => :optional

  # Upstream PR from 17 Apr 2018 "Boost 1.67.0 compatibility"
  patch do
    url "https://github.com/gnuradio/gnuradio/pull/1733.patch?full_index=1"
    sha256 "f02a04fb179a9b525b5e4ba8171ce5737c16d64f06f0e318ce092c6b4e19025f"
  end

  # cheetah starts here
  resource "Markdown" do
    url "https://files.pythonhosted.org/packages/1d/25/3f6d2cb31ec42ca5bd3bfbea99b63892b735d76e26f20dd2dcc34ffe4f0d/Markdown-2.6.8.tar.gz"
    sha256 "0ac8a81e658167da95d063a9279c9c1b2699f37c7c4153256a458b3a43860e33"
  end

  resource "Cheetah" do
    url "https://files.pythonhosted.org/packages/cd/b0/c2d700252fc251e91c08639ff41a8a5203b627f4e0a2ae18a6b662ab32ea/Cheetah-2.4.4.tar.gz"
    sha256 "be308229f0c1e5e5af4f27d7ee06d90bb19e6af3059794e5fd536a6f29a9b550"
  end
  # cheetah ends here

  resource "lxml" do
    url "https://files.pythonhosted.org/packages/39/e8/a8e0b1fa65dd021d48fe21464f71783655f39a41f218293c1c590d54eb82/lxml-3.7.3.tar.gz"
    sha256 "aa502d78a51ee7d127b4824ff96500f0181d3c7826e6ee7b800d068be79361c7"
  end

  resource "cppzmq" do
    url "https://raw.githubusercontent.com/zeromq/cppzmq/46fc0572c5e9f09a32a23d6f22fd79b841f77e00/zmq.hpp"
    sha256 "964031c0944f913933f55ad1610938105a6657a69d1ac5a6dd50e16a679104d5"
  end

  def install
    ENV.prepend_path "PATH", "/System/Library/Frameworks/Python.framework/Versions/2.7/bin"

    ENV["CHEETAH_INSTALL_WITHOUT_SETUPTOOLS"] = "1"
    ENV["XML_CATALOG_FILES"] = etc/"xml/catalog"
    ENV.prepend_create_path "PYTHONPATH", libexec/"vendor/lib/python2.7/site-packages"

    ["Markdown", "Cheetah"].each do |r|
      resource(r).stage do
        system "python", *Language::Python.setup_install_args(libexec/"vendor")
      end
    end

    begin
      # Fix "ld: file not found: /usr/lib/system/libsystem_darwin.dylib" for lxml
      ENV["SDKROOT"] = MacOS.sdk_path if MacOS.version == :sierra

      resource("lxml").stage do
        system "python", *Language::Python.setup_install_args(libexec/"vendor")
      end
    ensure
      ENV.delete("SDKROOT")
    end

    resource("cppzmq").stage include.to_s

    args = std_cmake_args
    args << "-DGR_PKG_CONF_DIR=#{etc}/gnuradio/conf.d"
    args << "-DGR_PREFSDIR=#{etc}/gnuradio/conf.d"

    args << "-DENABLE_DEFAULT=OFF"
    enabled_components = %w[gr-analog gr-fft volk gr-filter gnuradio-runtime
                            gr-blocks gr-pager gr-noaa gr-channels gr-audio
                            gr-fcd gr-vocoder gr-fec gr-digital gr-dtv gr-atsc
                            gr-trellis gr-zeromq]
    if build.with? "python@2"
      enabled_components << "python"
      enabled_components << "gr-utils"
      enabled_components << "grc" if build.with? "pygtk"
      enabled_components << "gr-wxgui" if build.with? "wxpython"
    end
    enabled_components << "gr-wavelet"
    enabled_components << "gr-video-sdl" if build.with? "sdl"
    enabled_components << "gr-uhd" if build.with? "uhd"
    enabled_components << "doxygen" if build.with? "doxygen"
    enabled_components << "sphinx" if build.with? "sphinx"

    enabled_components.each do |c|
      args << "-DENABLE_#{c.upcase.split("-").join("_")}=ON"
    end

    mkdir "build" do
      system "cmake", "..", *args
      system "make"
      system "make", "install"
    end

    rm bin.children.reject(&:executable?)
    bin.env_script_all_files(libexec/"bin", :PYTHONPATH => ENV["PYTHONPATH"])
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/gnuradio-config-info -v")

    (testpath/"test.c++").write <<~EOS
      #include <gnuradio/top_block.h>
      #include <gnuradio/blocks/null_source.h>
      #include <gnuradio/blocks/null_sink.h>
      #include <gnuradio/blocks/head.h>
      #include <gnuradio/gr_complex.h>

      class top_block : public gr::top_block {
      public:
        top_block();
      private:
        gr::blocks::null_source::sptr null_source;
        gr::blocks::null_sink::sptr null_sink;
        gr::blocks::head::sptr head;
      };

      top_block::top_block() : gr::top_block("Top block") {
        long s = sizeof(gr_complex);
        null_source = gr::blocks::null_source::make(s);
        null_sink = gr::blocks::null_sink::make(s);
        head = gr::blocks::head::make(s, 1024);
        connect(null_source, 0, head, 0);
        connect(head, 0, null_sink, 0);
      }

      int main(int argc, char **argv) {
        top_block top;
        top.run();
      }
    EOS
    system ENV.cxx, "-L#{lib}", "-L#{Formula["boost"].opt_lib}",
           "-lgnuradio-blocks", "-lgnuradio-runtime", "-lgnuradio-pmt",
           "-lboost_system", testpath/"test.c++", "-o", testpath/"test"
    system "./test"

    if build.with? "python@2"
      (testpath/"test.py").write <<~EOS
        from gnuradio import blocks
        from gnuradio import gr

        class top_block(gr.top_block):
            def __init__(self):
                gr.top_block.__init__(self, "Top Block")
                self.samp_rate = 32000
                s = gr.sizeof_gr_complex
                self.blocks_null_source_0 = blocks.null_source(s)
                self.blocks_null_sink_0 = blocks.null_sink(s)
                self.blocks_head_0 = blocks.head(s, 1024)
                self.connect((self.blocks_head_0, 0),
                             (self.blocks_null_sink_0, 0))
                self.connect((self.blocks_null_source_0, 0),
                             (self.blocks_head_0, 0))

        def main(top_block_cls=top_block, options=None):
            tb = top_block_cls()
            tb.start()
            tb.wait()

        main()
      EOS
      system "python2.7", testpath/"test.py"

      cd testpath do
        system "#{bin}/gr_modtool", "newmod", "test"

        cd "gr-test" do
          system "#{bin}/gr_modtool", "add", "-t", "general", "test_ff", "-l",
                 "python", "-y", "--argument-list=''", "--add-python-qa"
        end
      end
    end
  end
end
