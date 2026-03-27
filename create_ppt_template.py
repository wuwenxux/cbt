#!/usr/bin/env python3

from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.enum.text import PP_ALIGN
from pptx.dml.color import RGBColor
import os

def create_project_ppt():
    """创建项目总结PPT模板"""
    
    # 创建演示文稿
    prs = Presentation()
    
    # 设置幻灯片尺寸为16:9
    prs.slide_width = Inches(13.33)
    prs.slide_height = Inches(7.5)
    
    # 1. 标题页
    slide1 = prs.slides.add_slide(prs.slide_layouts[0])  # 标题布局
    title = slide1.shapes.title
    subtitle = slide1.placeholders[1]
    
    title.text = "睿思芯科员工答辩 PPT"
    subtitle.text = "答辩人： 邬文轩\n答辩时间： 2025年10月10日"
    
    # 设置标题样式
    title.text_frame.paragraphs[0].font.size = Pt(24)
    title.text_frame.paragraphs[0].font.bold = True
    title.text_frame.paragraphs[0].font.color.rgb = RGBColor(0, 51, 102)
    
    subtitle.text_frame.paragraphs[0].font.size = Pt(24)
    subtitle.text_frame.paragraphs[0].font.color.rgb = RGBColor(102, 102, 102)
    
    # 2. 目录页
    slide2 = prs.slides.add_slide(prs.slide_layouts[0])  # 使用标题布局
    title2 = slide2.shapes.title
    subtitle2 = slide2.shapes.placeholders[1]  # 副标题占位符
    
    title2.text = "目录"
    subtitle2.text = """1. 自我介绍
2. 工作产出及学习情况
3. 自我评价
4. 后续工作展望"""
    
    # 设置副标题格式
    for paragraph in subtitle2.text_frame.paragraphs:
        if paragraph.text.strip():
            paragraph.font.size = Pt(22)  # 副标题字体大小
            paragraph.font.bold = False
            paragraph.font.color.rgb = RGBColor(64, 64, 64)  # 深灰色
            paragraph.line_spacing = 1.2
            # 清除项目符号
            try:
                paragraph.font.bullet.type = None
            except:
                pass
    
    # 3. 自我介绍
    slide3 = prs.slides.add_slide(prs.slide_layouts[1])  # 使用内容布局
    title3 = slide3.shapes.title
    content3 = slide3.placeholders[1]  # 内容占位符
    
    title3.text = "自我介绍"
    content3.text = """多年Linux服务器、嵌入式相关网络开发经验
对网络运维、驱动、协议、应用、性能有比较丰富的积累和实践
参与过Intel、电网、通用、无人机、中科院等商业化网络项目
项目Onwer实现多个网络项目并且在开源社区持续维护迭代
"""
    
    # 4. 工作产出
    slide4 = prs.slides.add_slide(prs.slide_layouts[0])  # 使用标题布局
    title4 = slide4.shapes.title
    subtitle4 = slide4.shapes.placeholders[1]  # 副标题占位符
    
    title4.text = "工作产出"
    subtitle4.text = """项目目标：RISC-V Ceph自动化部署
技术栈：RISC-V、QEMU、Ceph、CBT、Shell、Python

主要成果：
• RISC-V QEMU虚拟化环境搭建
• RISC-V环境下的Ceph环境准备  
• RISC-V架构下的Ceph部署以及性能测试
• RISC-V Ceph文档与知识整理
• DPDK基于RISC-V的工作内容梳理"""
    
    # 5. 自我评价
    slide5 = prs.slides.add_slide(prs.slide_layouts[0])  # 使用标题布局
    title5 = slide5.shapes.title
    subtitle5 = slide5.shapes.placeholders[1]  # 副标题占位符
    
    title5.text = "自我评价"
    content5.text = """✅ 优点
系统性思维：从RISC-V生态整体角度分析问题
问题解决能力：逐步分解和定位复杂技术问题
学习能力：快速掌握RISC-V、Ceph等相关知识

⚠️ 不足
深度不够：对RISC-V底层架构原理理解还需深入
经验积累：复杂系统故障处理需要更多实践"""
    
    # 6. RISC-V生态深入学习计划
    slide6 = prs.slides.add_slide(prs.slide_layouts[1])
    title6 = slide6.shapes.title
    content6 = slide6.placeholders[1]
    
    title6.text = "RISC-V生态深入学习计划"
    content6.text = """🎯 短期目标（1-2个月）
深入学习RISC-V架构：指令集、微架构设计
虚拟化技术：QEMU、KVM、容器化技术

🎯 中长期目标（3-6个月）
RISC-V生态工具链：编译器、调试器、性能分析工具
操作系统：Linux RISC-V网络驱动（用户态、内核态）开发、验证、优化、重构"""
    
    # 7. RISC-V技术栈扩展计划
    slide7 = prs.slides.add_slide(prs.slide_layouts[1])
    title7 = slide7.shapes.title
    content7 = slide7.placeholders[1]
    
    title7.text = "RISC-V技术栈扩展计划"
    content7.text = """🔧 RISC-V硬件技术
SoC设计、FPGA开发、ASIC设计
硬件描述语言：Verilog、SystemVerilog

📊 RISC-V软件生态
编译器工具链：GCC、LLVM、Rust
操作系统：Linux、FreeBSD、Zephyr"""
    
    # 8. RISC-V网络驱动开发
    slide8 = prs.slides.add_slide(prs.slide_layouts[1])
    title8 = slide8.shapes.title
    content8 = slide8.placeholders[1]
    
    title8.text = "RISC-V网络驱动开发"
    content8.text = """🌐 用户态网络驱动
用户态网络驱动实现和优化
内核态网络驱动性能调优
网络协议栈移植和适配

🔧 网络性能优化
网络I/O性能基准测试
零拷贝技术实现
多核网络处理优化"""
    
    # 9. RISC-V网络测试验证
    slide9 = prs.slides.add_slide(prs.slide_layouts[1])
    title9 = slide9.shapes.title
    content9 = slide9.placeholders[1]
    
    title9.text = "RISC-V网络测试验证"
    content9.text = """📊 网络性能测试
网络性能基准测试框架
网络延迟和吞吐量分析
网络驱动稳定性测试

🎯 测试工具开发
自动化测试框架
性能监控工具
压力测试工具"""
    
    # 10. RISC-V网络技术发展方向
    slide10 = prs.slides.add_slide(prs.slide_layouts[1])
    title10 = slide10.shapes.title
    content10 = slide10.placeholders[1]
    
    title10.text = "RISC-V网络技术发展方向"
    content10.text = """🎯 技术发展方向
深入RISC-V网络驱动架构设计
网络性能优化和调优技术
网络协议栈在RISC-V上的适配

🚀 实践目标
开发高性能RISC-V网络驱动
建立RISC-V网络性能测试体系"""
    
    # 11. RISC-V网络技术价值
    slide11 = prs.slides.add_slide(prs.slide_layouts[1])
    title11 = slide11.shapes.title
    content11 = slide11.placeholders[1]
    
    title11.text = "RISC-V网络技术价值"
    content11.text = """📈 技术价值
提升RISC-V在网络领域的竞争力
为RISC-V生态贡献网络技术
推动开源网络技术发展

🌟 生态贡献
推动RISC-V网络生态发展
建立技术标准和规范
培养RISC-V网络技术人才"""
    
    # 为所有幻灯片设置字体大小
    for slide in prs.slides:
        # 设置标题字体
        if slide.shapes.title:
            for paragraph in slide.shapes.title.text_frame.paragraphs:
                if paragraph.text.strip():
                    paragraph.font.size = Pt(44)
                    paragraph.font.bold = True
        
        # 设置副标题样式
        for shape in slide.shapes:
            if hasattr(shape, "text_frame") and shape != slide.shapes.title:
                for paragraph in shape.text_frame.paragraphs:
                    if paragraph.text.strip():
                        # 副标题样式设置
                        paragraph.font.size = Pt(22)  # 副标题字体大小
                        paragraph.font.bold = False
                        paragraph.font.color.rgb = RGBColor(64, 64, 64)  # 深灰色
                        # 设置行间距
                        paragraph.line_spacing = 1.2
                        # 清除项目符号
                        try:
                            from pptx.enum.text import PP_PARAGRAPH_ALIGNMENT
                            paragraph.alignment = PP_PARAGRAPH_ALIGNMENT.LEFT
                            # 尝试清除项目符号
                            if hasattr(paragraph, 'font') and hasattr(paragraph.font, 'bullet'):
                                paragraph.font.bullet.type = None
                        except:
                            pass
    
    # 保存PPT
    output_file = "/work/home/wenxuan/Projects/cbt/员工答辩PPT.pptx"
    prs.save(output_file)
    print(f"PPT模板已创建：{output_file}")
    
    return output_file

if __name__ == "__main__":
    create_project_ppt()
