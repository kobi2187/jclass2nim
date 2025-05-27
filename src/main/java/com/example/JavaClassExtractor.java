package com.example;
import com.github.javaparser.StaticJavaParser;
import com.github.javaparser.ast.CompilationUnit;
import com.github.javaparser.ast.body.*;
import com.github.javaparser.ast.visitor.VoidVisitorAdapter;
import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;

public class JavaClassExtractor {
    
    public static void main(String[] args) {
        if (args.length < 1) {
            System.out.println("Usage: JavaClassExtractor <java_file> [output_file]");
            System.exit(1);
        }
        
        String inputFile = args[0];
        String outputFile = args.length > 1 ? args[1] : null;
        
        try {
            File file = new File(inputFile);
            if (file.isDirectory()) {
                processDirectory(file);
            } else {
                JSONArray classesJson = processFile(file);
                String json = classesJson.toString(2);
                
                if (outputFile != null) {
                    Files.write(Paths.get(outputFile), json.getBytes());
                    System.out.println("Wrote output to " + outputFile);
                } else {
                    System.out.println(json);
                }
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
    
    private static void processDirectory(File dir) throws Exception {
        File[] files = dir.listFiles();
        if (files == null) return;
        
        for (File file : files) {
            if (file.isDirectory()) {
                processDirectory(file);
            } else if (file.getName().endsWith(".java")) {
                try {
                    String outputFile = file.getPath().replaceAll("\\.java$", ".json");
                    JSONArray classesJson = processFile(file);
                    
                    if (classesJson.length() > 0) {
                        Files.write(Paths.get(outputFile), classesJson.toString(2).getBytes());
                        System.out.println("Processed " + file.getPath() + " -> " + outputFile);
                    } else {
                        System.out.println("No classes found in " + file.getPath());
                    }
                } catch (Exception e) {
                    System.err.println("Error processing file " + file.getPath() + ": " + e.getMessage());
                }
            }
        }
    }
    
    private static JSONArray processFile(File file) throws FileNotFoundException {
        CompilationUnit cu = StaticJavaParser.parse(file);
        return extractClasses(cu, file.getAbsolutePath());
    }
    
    private static JSONArray extractClasses(CompilationUnit cu, String filePath) {
        JSONArray classesJson = new JSONArray();
        String packageName = cu.getPackageDeclaration().isPresent() ? 
                             cu.getPackageDeclaration().get().getNameAsString() : "";
        
        // Class collector visitor
        ClassCollectorVisitor visitor = new ClassCollectorVisitor(packageName);
        visitor.visit(cu, classesJson);
        
        return classesJson;
    }
    
    // Visitor class to collect class information
    private static class ClassCollectorVisitor extends VoidVisitorAdapter<JSONArray> {
        private String packageName;
        
        public ClassCollectorVisitor(String packageName) {
            this.packageName = packageName;
        }
        
        @Override
        public void visit(ClassOrInterfaceDeclaration classDecl, JSONArray classesJson) {
            // Only process public classes
            if (!classDecl.isPublic()) {
                super.visit(classDecl, classesJson);
                return;
            }
            
            JSONObject classJson = new JSONObject();
            classJson.put("name", classDecl.getNameAsString());
            classJson.put("full_name", classDecl.getNameAsString());
            classJson.put("package", packageName);
            classJson.put("is_interface", classDecl.isInterface());
            
            // Get superclass if any
            if (classDecl.getExtendedTypes().size() > 0) {
                classJson.put("superclass", 
                    classDecl.getExtendedTypes().get(0).getNameAsString());
            }
            
            // Extract modifiers
            JSONArray modifiersJson = new JSONArray();
            classDecl.getModifiers().forEach(modifier -> 
                modifiersJson.put(modifier.toString().trim()));
            classJson.put("modifiers", modifiersJson);
            
            // Extract methods
            JSONArray methodsJson = new JSONArray();
            classDecl.getMethods().forEach(method -> {
                if (method.isPublic()) {
                    JSONObject methodJson = new JSONObject();
                    methodJson.put("name", method.getNameAsString());
                    methodJson.put("return_type", method.getType().asString());
                    
                    // Method modifiers
                    JSONArray methodModifiersJson = new JSONArray();
                    method.getModifiers().forEach(modifier -> 
                        methodModifiersJson.put(modifier.toString().trim()));
                    methodJson.put("modifiers", methodModifiersJson);
                    
                    // Method parameters
                    JSONArray paramsJson = new JSONArray();
                    method.getParameters().forEach(param -> {
                        JSONObject paramJson = new JSONObject();
                        paramJson.put("type", param.getType().asString());
                        paramJson.put("name", param.getNameAsString());
                        paramsJson.put(paramJson);
                    });
                    methodJson.put("parameters", paramsJson);
                    
                    methodsJson.put(methodJson);
                }
            });
            classJson.put("methods", methodsJson);
            
            // Extract fields
            JSONArray fieldsJson = new JSONArray();
            classDecl.getFields().forEach(field -> {
                if (field.isPublic()) {
                    field.getVariables().forEach(var -> {
                        JSONObject fieldJson = new JSONObject();
                        fieldJson.put("name", var.getNameAsString());
                        fieldJson.put("type", field.getElementType().asString());
                        
                        // Field modifiers
                        JSONArray fieldModifiersJson = new JSONArray();
                        field.getModifiers().forEach(modifier -> 
                            fieldModifiersJson.put(modifier.toString().trim()));
                        fieldJson.put("modifiers", fieldModifiersJson);
                        
                        fieldsJson.put(fieldJson);
                    });
                }
            });
            classJson.put("fields", fieldsJson);
            
            // Process nested classes
            JSONArray nestedClassesJson = new JSONArray();
            for (BodyDeclaration<?> member : classDecl.getMembers()) {
                if (member instanceof ClassOrInterfaceDeclaration) {
                    ClassOrInterfaceDeclaration nestedClass = (ClassOrInterfaceDeclaration) member;
                    if (nestedClass.isPublic()) {
                        JSONObject nestedClassJson = new JSONObject();
                        nestedClassJson.put("name", nestedClass.getNameAsString());
                        nestedClassJson.put("full_name", classDecl.getNameAsString() + "." + nestedClass.getNameAsString());
                        nestedClassJson.put("package", packageName);
                        nestedClassJson.put("is_interface", nestedClass.isInterface());
                        
                        // Extract nested class details - methods, fields, etc.
                        // You can extract these similar to the parent class
                        
                        // Extract methods of nested class
                        JSONArray nestedMethodsJson = new JSONArray();
                        nestedClass.getMethods().forEach(method -> {
                            if (method.isPublic()) {
                                JSONObject methodJson = new JSONObject();
                                methodJson.put("name", method.getNameAsString());
                                methodJson.put("return_type", method.getType().asString());
                                
                                // Method modifiers
                                JSONArray methodModifiersJson = new JSONArray();
                                method.getModifiers().forEach(modifier -> 
                                    methodModifiersJson.put(modifier.toString().trim()));
                                methodJson.put("modifiers", methodModifiersJson);
                                
                                // Method parameters
                                JSONArray nestedParamsJson = new JSONArray();
                                method.getParameters().forEach(param -> {
                                    JSONObject paramJson = new JSONObject();
                                    paramJson.put("type", param.getType().asString());
                                    paramJson.put("name", param.getNameAsString());
                                    nestedParamsJson.put(paramJson);
                                });
                                methodJson.put("parameters", nestedParamsJson);
                                
                                nestedMethodsJson.put(methodJson);
                            }
                        });
                        nestedClassJson.put("methods", nestedMethodsJson);
                        
                        // Add nested class to array
                        nestedClassesJson.put(nestedClassJson);
                    }
                }
            }
            classJson.put("nested_classes", nestedClassesJson);
            
            // Add class to JSON array
            classesJson.put(classJson);
            
            // Continue with visitor pattern
            super.visit(classDecl, classesJson);
        }
    }
}