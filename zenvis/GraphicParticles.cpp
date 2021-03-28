#include "stdafx.hpp"
#include "ShaderProgram.hpp"
#include "IGraphic.hpp"
#include "main.hpp"

namespace zenvis {

struct GraphicParticles : IGraphic {
  static inline std::unique_ptr<ShaderProgram> prog_;

  size_t vertex_count;
  std::unique_ptr<Buffer> vbo;

  explicit GraphicParticles(std::vector<char> const &serial) {
    vertex_count = serial.size() / (6 * sizeof(float));

    vbo = std::make_unique<Buffer>(GL_ARRAY_BUFFER);
    vbo->bind_data(serial.data(), serial.size());
  }

  virtual void draw() override {
    if (vertex_updated) {
      vbo = std::make_unique<Buffer>(GL_ARRAY_BUFFER);
      vbo->bind_data(vertex_data);
      vertex_updated = false;
    }

    auto pro = get_program();
    set_program_uniforms(pro);

    vbo->bind();
    vbo->attribute(/*index=*/0,
        /*offset=*/sizeof(float) * 0, /*stride=*/sizeof(float) * 6,
        GL_FLOAT, /*count=*/3);
    vbo->attribute(/*index=*/1,
        /*offset=*/sizeof(float) * 3, /*stride=*/sizeof(float) * 6,
        GL_FLOAT, /*count=*/3);
    CHECK_GL(glDrawArrays(GL_POINTS, /*first=*/0, /*count=*/vertex_count));
    vbo->disable_attribute(0);
    vbo->disable_attribute(1);
    vbo->unbind();
  }

  Program *get_program() {
    if (!prog_)
      prog_ = std::make_unique<ShaderProgram>("particles");
    auto pro = prog_.get();
    pro->use();
    return pro;
  }
};

std::unique_ptr<IGraphic> makeGraphicParticles(std::vector<char> const &serial) {
  return std::make_unique<GraphicParticles>(serial);
}

}
