class Csound < Formula
  desc "Sound and music computing system"
  homepage "https://csound.com"
  url "https://github.com/csound/csound/archive/6.14.0.tar.gz"
  sha256 "bef349c5304b2d3431ef417933b4c9e9469c0a408a4fa4a98acf0070af360a22"
  head "https://github.com/csound/csound.git", :branch => "develop"

  bottle do
    sha256 "c4e9ff3ef8d8b2cc55ceb1de117a70f3135f1ee02a329a309e3b25e1387fe052" => :catalina
    sha256 "318360d3f96d136816fbe3b6f7e6b91b24279a3c2510fb930bc50d5742c6e8c5" => :mojave
    sha256 "257925fdd36a76c78a51112f4fc86c438102c05d98fc91723d537c34cef16c73" => :high_sierra
  end

  depends_on "asio" => :build
  depends_on "cmake" => :build
  depends_on "eigen" => :build
  depends_on "swig" => :build
  depends_on "faust"
  depends_on "fltk"
  depends_on "fluid-synth"
  depends_on "gettext"
  depends_on "hdf5"
  depends_on "jack"
  depends_on :java
  depends_on "liblo"
  depends_on "libpng"
  depends_on "libsamplerate"
  depends_on "libsndfile"
  depends_on "numpy"
  depends_on "portaudio"
  depends_on "portmidi"
  depends_on "stk"
  depends_on "wiiuse"
  uses_from_macos "bison" => :build
  uses_from_macos "flex" => :build
  uses_from_macos "curl"
  uses_from_macos "python@2"
  uses_from_macos "zlib"

  conflicts_with "libextractor", :because => "both install `extract` binaries"
  conflicts_with "pkcrack", :because => "both install `extract` binaries"

  resource "ableton-link" do
    url "https://github.com/Ableton/link/archive/Link-3.0.2.tar.gz"
    sha256 "2716e916a9dd9445b2a4de1f2325da818b7f097ec7004d453c83b10205167100"
  end

  resource "getfem" do
    url "https://download.savannah.gnu.org/releases/getfem/stable/getfem-5.3.tar.gz"
    sha256 "9d10a1379fca69b769c610c0ee93f97d3dcb236d25af9ae4cadd38adf2361749"
  end

  def install
    resource("ableton-link").stage { cp_r "include/ableton", buildpath }
    resource("getfem").stage { cp_r "src/gmm", buildpath }

    args = std_cmake_args + %W[
      -DABLETON_LINK_HOME=#{buildpath}/ableton
      -DBUILD_ABLETON_LINK_OPCODES=ON
      -DBUILD_JAVA_INTERFACE=ON
      -DBUILD_LINEAR_ALGEBRA_OPCODES=ON
      -DBUILD_LUA_INTERFACE=OFF
      -DBUILD_PYTHON_INTERFACE=OFF
      -DBUILD_WEBSOCKET_OPCODE=OFF
      -DCMAKE_INSTALL_RPATH=#{frameworks}
      -DCS_FRAMEWORK_DEST=#{frameworks}
      -DGMM_INCLUDE_DIR=#{buildpath}/gmm
      -DJAVA_MODULE_INSTALL_DIR=#{libexec}
    ]

    mkdir "build" do
      system "cmake", "..", *args
      system "make", "install"
    end

    include.install_symlink frameworks/"CsoundLib64.framework/Headers" => "csound"

    libexec.install buildpath/"interfaces/ctcsound.py"

    python_version = Language::Python.major_minor_version "python3"
    (lib/"python#{python_version}/site-packages/homebrew-csound.pth").write <<~EOS
      import site; site.addsitedir('#{libexec}')
    EOS
  end

  def caveats; <<~EOS
    To use the Python bindings, you may need to add to #{shell_profile}:
      export DYLD_FRAMEWORK_PATH="$DYLD_FRAMEWORK_PATH:#{opt_frameworks}"

    To use the Java bindings, you may need to add to #{shell_profile}:
      export CLASSPATH='#{opt_libexec}/csnd6.jar:.'
    and link the native shared library into your Java Extensions folder:
      mkdir -p ~/Library/Java/Extensions
      ln -s '#{opt_libexec}/lib_jcsound6.jnilib' ~/Library/Java/Extensions
  EOS
  end

  test do
    (testpath/"test.orc").write <<~EOS
      0dbfs = 1
      gi_peer link_create
      gi_programHandle faustcompile "process = _;", "--vectorize --loop-variant 1"
      FLrun
      gi_fluidEngineNumber fluidEngine
      gi_image imagecreate 1, 1
      gi_realVector la_i_vr_create 1
      pyinit
      pyruni "print('hello, world')"
      instr 1
          a_, a_, a_ chuap 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
          a_signal STKPlucked 440, 1
          hdf5write "test.h5", a_signal
          out a_signal
      endin
    EOS

    (testpath/"test.sco").write <<~EOS
      i 1 0 1
      e
    EOS

    ENV["OPCODE6DIR64"] = frameworks/"CsoundLib64.framework/Resources/Opcodes64"
    ENV["RAWWAVE_PATH"] = Formula["stk"].pkgshare/"rawwaves"

    output = shell_output "#{bin}/csound test.orc test.sco 2>&1"
    assert_match /^hello, world$/, output
    assert_match /^rtaudio:/, output
    assert_match /^rtmidi:/, output

    assert_predicate testpath/"test.aif", :exist?
    assert_predicate testpath/"test.h5", :exist?

    (testpath/"opcode-existence.orc").write <<~EOS
      JackoInfo
      instr 1
          i_success wiiconnect 1, 1
      endin
    EOS
    system bin/"csound", "--orc", "--syntax-check-only", "opcode-existence.orc"

    ENV["DYLD_FRAMEWORK_PATH"] = frameworks
    system "python3", "-c", "import ctcsound"
    ENV.delete("DYLD_FRAMEWORK_PATH")

    (testpath/"test.java").write <<~EOS
      import csnd6.*;
      public class test {
          public static void main(String args[]) {
              csnd6.csoundInitialize(csnd6.CSOUNDINIT_NO_ATEXIT | csnd6.CSOUNDINIT_NO_SIGNAL_HANDLER);
          }
      }
    EOS
    system "javac", "-classpath", "#{libexec}/csnd6.jar", "test.java"
    system "java", "-classpath", "#{libexec}/csnd6.jar:.", "-Djava.library.path=#{libexec}", "test"
  end
end
